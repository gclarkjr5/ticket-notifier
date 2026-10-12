# ticket-alert

Rust (axum) service. On every Pub/Sub push it searches Gmail for mail matching `SENDER` /
`SUBJECT` that isn't yet labelled `ticket-notified`, extracts the first link matching
`LINK_PATTERN`, sends an urgent ntfy notification (tapping it opens the link), then labels the
mail. The label is the only state, so retried or duplicate pushes can't double-notify.

Endpoints: `POST /` (Pub/Sub push), `POST /renew` (re-register the Gmail watch),
`GET /healthz`. Both POSTs expect Cloud Run IAM auth (handled by the infra).

## Config (env vars; set by `infra/`)
| var | meaning |
|---|---|
| GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / GOOGLE_REFRESH_TOKEN | OAuth, scope `gmail.modify` |
| SENDER | Gmail `from:` value; display name or address (`Celebratix`) |
| SUBJECT | optional Gmail `subject:` phrase (`SPIELRAUM WEEKENDER OCT`) |
| LINK_PATTERN | regex the link must match |
| NTFY_TOPIC / NTFY_SERVER | where alerts go (default server `https://ntfy.sh`) |
| PUBSUB_TOPIC | `projects/<p>/topics/gmail-push`, used by `/renew` |

## Develop
```sh
cargo test
```
Tests cover MIME decoding, `&amp;` unescaping and the Celebratix link pattern.
