mod extract;

use anyhow::{anyhow, Context, Result};
use axum::{
    http::StatusCode,
    routing::{get, post},
    Router,
};
use regex::Regex;
use serde_json::{json, Value};
use std::{
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::sync::Mutex;

const GMAIL: &str = "https://gmail.googleapis.com/gmail/v1/users/me";
const DONE_LABEL: &str = "ticket-notified";

struct Config {
    client_id: String,
    client_secret: String,
    refresh_token: String,
    sender: String,
    subject: Option<String>,
    link_pattern: Regex,
    ntfy_server: String,
    ntfy_topic: String,
    pubsub_topic: Option<String>,
}

struct State {
    cfg: Config,
    http: reqwest::Client,
    // Serialises processing so concurrent pushes can't double-notify.
    inner: Mutex<Inner>,
}

#[derive(Default)]
struct Inner {
    token: Option<(String, Instant)>,
    label_id: Option<String>,
}

fn env(k: &str) -> Result<String> {
    std::env::var(k).with_context(|| format!("missing env var {k}"))
}

impl Config {
    fn from_env() -> Result<Self> {
        Ok(Self {
            client_id: env("GOOGLE_CLIENT_ID")?,
            client_secret: env("GOOGLE_CLIENT_SECRET")?,
            refresh_token: env("GOOGLE_REFRESH_TOKEN")?,
            sender: env("SENDER")?,
            subject: std::env::var("SUBJECT").ok().filter(|s| !s.is_empty()),
            link_pattern: Regex::new(&env("LINK_PATTERN")?).context("bad LINK_PATTERN")?,
            ntfy_server: std::env::var("NTFY_SERVER").unwrap_or_else(|_| "https://ntfy.sh".into()),
            ntfy_topic: env("NTFY_TOPIC")?,
            pubsub_topic: std::env::var("PUBSUB_TOPIC").ok(),
        })
    }
}

impl State {
    async fn access_token(&self, inner: &mut Inner) -> Result<String> {
        if let Some((t, exp)) = &inner.token {
            if Instant::now() < *exp {
                return Ok(t.clone());
            }
        }
        let r: Value = self
            .http
            .post("https://oauth2.googleapis.com/token")
            .form(&[
                ("client_id", self.cfg.client_id.as_str()),
                ("client_secret", self.cfg.client_secret.as_str()),
                ("refresh_token", self.cfg.refresh_token.as_str()),
                ("grant_type", "refresh_token"),
            ])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let tok = r["access_token"]
            .as_str()
            .ok_or_else(|| anyhow!("no access_token"))?
            .to_string();
        let ttl = r["expires_in"].as_u64().unwrap_or(3600).saturating_sub(60);
        inner.token = Some((tok.clone(), Instant::now() + Duration::from_secs(ttl)));
        Ok(tok)
    }

    async fn get(&self, tok: &str, url: &str, q: &[(&str, &str)]) -> Result<Value> {
        Ok(self
            .http
            .get(url)
            .bearer_auth(tok)
            .query(q)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?)
    }

    async fn ensure_label(&self, tok: &str, inner: &mut Inner) -> Result<String> {
        if let Some(id) = &inner.label_id {
            return Ok(id.clone());
        }
        let list = self.get(tok, &format!("{GMAIL}/labels"), &[]).await?;
        let found = list["labels"].as_array().and_then(|ls| {
            ls.iter()
                .find(|l| l["name"] == DONE_LABEL)
                .and_then(|l| l["id"].as_str().map(String::from))
        });
        let id = match found {
            Some(id) => id,
            None => {
                let c: Value = self
                    .http
                    .post(format!("{GMAIL}/labels"))
                    .bearer_auth(tok)
                    .json(&json!({"name": DONE_LABEL}))
                    .send()
                    .await?
                    .error_for_status()?
                    .json()
                    .await?;
                c["id"]
                    .as_str()
                    .ok_or_else(|| anyhow!("label create failed"))?
                    .to_string()
            }
        };
        inner.label_id = Some(id.clone());
        Ok(id)
    }

    async fn notify(&self, title: &str, body: &str, click: Option<&str>) -> Result<()> {
        let mut req = self
            .http
            .post(format!("{}/{}", self.cfg.ntfy_server, self.cfg.ntfy_topic))
            .header("Title", title)
            .header("Priority", "urgent")
            .header("Tags", "ticket")
            .body(body.to_string());
        if let Some(u) = click {
            req = req.header("Click", u);
        }
        req.send().await?.error_for_status()?;
        Ok(())
    }

    /// Find unprocessed mail from SENDER, notify with the resale link, then label it done.
    async fn process(&self) -> Result<usize> {
        let mut inner = self.inner.lock().await;
        let tok = self.access_token(&mut inner).await?;
        let label_id = self.ensure_label(&tok, &mut inner).await?;

        let mut q = format!(
            "from:{} -label:{} newer_than:1d",
            self.cfg.sender, DONE_LABEL
        );
        if let Some(subj) = &self.cfg.subject {
            q.push_str(&format!(" subject:\"{}\"", subj.replace('"', "")));
        }
        let list = self
            .get(
                &tok,
                &format!("{GMAIL}/messages"),
                &[("q", &q), ("maxResults", "10")],
            )
            .await?;
        let ids: Vec<String> = list["messages"]
            .as_array()
            .map(|a| {
                a.iter()
                    .filter_map(|m| m["id"].as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();

        for id in &ids {
            let msg = self
                .get(
                    &tok,
                    &format!("{GMAIL}/messages/{id}"),
                    &[("format", "full")],
                )
                .await?;
            let mut bodies = vec![];
            extract::collect_bodies(&msg["payload"], &mut bodies);
            let snippet = msg["snippet"].as_str().unwrap_or("");

            match extract::pick_link(&bodies, &self.cfg.link_pattern) {
                Some(link) => {
                    tracing::info!(%id, %link, "notifying");
                    self.notify("Ticket resale!", &format!("{snippet}\n{link}"), Some(&link))
                        .await?;
                }
                None => {
                    tracing::warn!(%id, "no matching link");
                    self.notify(
                        "Ticket email, no link matched",
                        snippet,
                        Some(&format!("https://mail.google.com/mail/u/0/#all/{id}")),
                    )
                    .await?;
                }
            }
            // Only mark done after the notification succeeded, so failures retry.
            self.http
                .post(format!("{GMAIL}/messages/{id}/modify"))
                .bearer_auth(&tok)
                .json(&json!({"addLabelIds": [label_id]}))
                .send()
                .await?
                .error_for_status()?;
        }
        Ok(ids.len())
    }

    async fn renew_watch(&self) -> Result<Value> {
        let topic = self
            .cfg
            .pubsub_topic
            .clone()
            .ok_or_else(|| anyhow!("PUBSUB_TOPIC not set"))?;
        let mut inner = self.inner.lock().await;
        let tok = self.access_token(&mut inner).await?;
        Ok(self.http.post(format!("{GMAIL}/watch")).bearer_auth(&tok)
            .json(&json!({"topicName": topic, "labelIds": ["INBOX"], "labelFilterBehavior": "INCLUDE"}))
            .send().await?.error_for_status()?.json().await?)
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt().init();
    let state = Arc::new(State {
        cfg: Config::from_env()?,
        http: reqwest::Client::builder()
            .timeout(Duration::from_secs(15))
            .build()?,
        inner: Mutex::default(),
    });

    // Pub/Sub push subscription -> POST /  (body ignored; we just re-scan for unprocessed mail)
    let s1 = state.clone();
    let s2 = state.clone();
    let app = Router::new()
        .route(
            "/",
            post(move || {
                let s = s1.clone();
                async move {
                    match s.process().await {
                        Ok(n) => {
                            tracing::info!(n, "processed");
                            StatusCode::OK
                        }
                        Err(e) => {
                            tracing::error!("{e:#}");
                            StatusCode::INTERNAL_SERVER_ERROR
                        } // Pub/Sub retries
                    }
                }
            }),
        )
        // Cloud Scheduler -> POST /renew daily
        .route(
            "/renew",
            post(move || {
                let s = s2.clone();
                async move {
                    match s.renew_watch().await {
                        Ok(v) => {
                            tracing::info!(?v, "watch renewed");
                            StatusCode::OK
                        }
                        Err(e) => {
                            tracing::error!("{e:#}");
                            StatusCode::INTERNAL_SERVER_ERROR
                        }
                    }
                }
            }),
        )
        .route("/healthz", get(|| async { "ok" }));

    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".into());
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{port}")).await?;
    axum::serve(listener, app).await?;
    Ok(())
}
