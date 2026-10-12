use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use regex::Regex;
use serde_json::Value;

/// Recursively collect decoded text/html and text/plain bodies from a Gmail payload.
pub fn collect_bodies(part: &Value, out: &mut Vec<String>) {
    let mime = part["mimeType"].as_str().unwrap_or("");
    if mime == "text/html" || mime == "text/plain" {
        if let Some(data) = part["body"]["data"].as_str() {
            // Gmail uses base64url, sometimes with padding.
            let clean = data.trim_end_matches('=');
            if let Ok(bytes) = URL_SAFE_NO_PAD.decode(clean) {
                out.push(String::from_utf8_lossy(&bytes).into_owned());
            }
        }
    }
    if let Some(parts) = part["parts"].as_array() {
        for p in parts {
            collect_bodies(p, out);
        }
    }
}

fn unescape(s: &str) -> String {
    s.replace("&amp;", "&")
        .replace("&#38;", "&")
        .replace("&#x3D;", "=")
        .replace("&#61;", "=")
}

/// All http(s) links in the bodies, in order, de-duplicated.
pub fn all_links(bodies: &[String]) -> Vec<String> {
    let href = Regex::new(r#"(?i)href\s*=\s*["']([^"']+)["']"#).unwrap();
    let bare = Regex::new(r#"https?://[^\s<>"')\]]+"#).unwrap();
    let mut links: Vec<String> = Vec::new();
    for b in bodies {
        for c in href.captures_iter(b) {
            links.push(unescape(&c[1]));
        }
        for m in bare.find_iter(b) {
            links.push(unescape(m.as_str()));
        }
    }
    let mut seen = std::collections::HashSet::new();
    links.retain(|l| l.starts_with("http") && seen.insert(l.clone()));
    links
}

/// First link matching the user's pattern.
pub fn pick_link(bodies: &[String], pattern: &Regex) -> Option<String> {
    all_links(bodies).into_iter().find(|l| pattern.is_match(l))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picks_matching_link_and_unescapes() {
        let html = r#"<a href="https://x.com/unsubscribe">u</a>
            <a href="https://tickets.example.com/resale/123?a=1&amp;b=2">Buy</a>"#;
        let re = Regex::new(r"tickets\.example\.com/resale/").unwrap();
        let got = pick_link(&[html.to_string()], &re).unwrap();
        assert_eq!(got, "https://tickets.example.com/resale/123?a=1&b=2");
    }

    #[test]
    fn decodes_nested_payload() {
        let data = URL_SAFE_NO_PAD.encode("see https://a.com/resale/9 now");
        let payload = serde_json::json!({
            "mimeType": "multipart/alternative",
            "parts": [{"mimeType": "text/plain", "body": {"data": data}}]
        });
        let mut out = vec![];
        collect_bodies(&payload, &mut out);
        let re = Regex::new("resale").unwrap();
        assert_eq!(pick_link(&out, &re).unwrap(), "https://a.com/resale/9");
    }

    #[test]
    fn celebratix_resale_links() {
        let re = Regex::new(r"^https://shop\.celebratix\.io/resale/[\w-]+(/[\w-]+)+").unwrap();
        let html = r#"<a href="https://celebratix.io/privacy">p</a>
            <a href="https://shop.celebratix.io/resale/4hxeg/2um96m/2wndcp/2y9ez544">Buy</a>"#;
        assert_eq!(
            pick_link(&[html.to_string()], &re).unwrap(),
            "https://shop.celebratix.io/resale/4hxeg/2um96m/2wndcp/2y9ez544"
        );
    }
}
