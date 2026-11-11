use serde_json::{json, Value};
use std::fs;
use std::path::Path;

pub async fn send(to: String, files: Vec<String>, text: Option<String>) -> String {
    // Resolve target IP/port
    let (ip, port) = if to.parse::<std::net::IpAddr>().is_ok() {
        (to.clone(), 53317u16)
    } else {
        // discovery scan
        match crate::discovery::scan(2000).await {
            s if s.contains(&to) => {
                // parse "alias ip:port" not robust; fallback to IP parse failed, try find line
                // We'll just use to as host with default port
                (to.clone(), 53317u16)
            }
            _ => (to.clone(), 53317u16),
        }
    };

    let client = match reqwest::Client::builder()
        .danger_accept_invalid_certs(true)
        .build() {
        Ok(c) => c,
        Err(e) => return format!("client error: {e}"),
    };

    // Build file list
    let mut payloads: Vec<(String, Vec<u8>, String)> = Vec::new(); // name, bytes, mime
    for f in &files {
        let p = Path::new(f);
        let name = p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_else(|| f.clone());
        match fs::read(p) {
            Ok(bytes) => {
                let mime = guess_mime(&name);
                payloads.push((name, bytes, mime));
            }
            Err(e) => return format!("read error {f}: {e}"),
        }
    }
    if let Some(t) = &text {
        payloads.push(("note.txt".to_string(), t.as_bytes().to_vec(), "text/plain".to_string()));
    }

    if payloads.is_empty() {
        return "no files to send".to_string();
    }

    // Build files map
    let mut files_map = serde_json::Map::new();
    let mut by_id: Vec<(String, (String, Vec<u8>, String))> = Vec::new();
    for (name, bytes, mime) in payloads {
        let id = uuid();
        files_map.insert(id.clone(), json!({
            "id": id,
            "fileName": name,
            "size": bytes.len(),
            "fileType": mime,
        }));
        by_id.push((id, (name, bytes, mime)));
    }

    let sender_info = json!({
        "alias": "localsend-mcp-rust",
        "version": "2.1",
        "deviceModel": "Mac",
        "deviceType": "desktop",
        "fingerprint": "rust-mcp",
        "port": 53317,
        "protocol": "https",
        "download": true,
    });

    let prepare_body = json!({ "info": sender_info, "files": files_map });
    let url = format!("https://{}:{}/api/localsend/v2/prepare-upload", ip, port);
    let resp = match client.post(&url).json(&prepare_body).send().await {
        Ok(r) => r,
        Err(e) => return format!("prepare request failed: {e}"),
    };
    if resp.status() == 204 {
        return "recipient declined".to_string();
    }
    let status = resp.status();
    if !status.is_success() {
        let body = resp.text().await.unwrap_or_default();
        return format!("prepare failed: {} {}", status, body);
    }
    let parsed: Value = match resp.json().await {
        Ok(v) => v,
        Err(e) => return format!("parse error: {e}"),
    };
    let session_id = parsed["sessionId"].as_str().unwrap_or("").to_string();
    let tokens = parsed["files"].as_object().cloned().unwrap_or_default();

    let mut results = Vec::new();
    let mut bytes_sent = 0usize;
    for (file_id, (_, (name, bytes, mime))) in by_id.iter().enumerate().map(|(i,(id,v))|(id.clone(), (i,v))) {
        // find token
        let token = match tokens.get(&file_id) {
            Some(v) => v.as_str().unwrap_or("").to_string(),
            None => { results.push(format!("{name}: no token")); continue; }
        };
        let upload_url = format!(
            "https://{}:{}/api/localsend/v2/upload?sessionId={}&fileId={}&token={}",
            ip, port, session_id, file_id, token
        );
        let up = client.post(&upload_url)
            .header("Content-Type", mime.clone())
            .header("Content-Length", bytes.len().to_string())
            .body(bytes.clone())
            .send().await;
        match up {
            Ok(r) if r.status().is_success() => {
                results.push(format!("{name}: ok"));
                bytes_sent += bytes.len();
            }
            Ok(r) => {
                let st = r.status();
                let b = r.text().await.unwrap_or_default();
                results.push(format!("{name}: HTTP {} {}", st, b));
            }
            Err(e) => results.push(format!("{name}: {e}")),
        }
    }

    format!("sent {} bytes\n{}", bytes_sent, results.join("\n"))
}

fn guess_mime(name: &str) -> String {
    let lower = name.to_lowercase();
    if lower.ends_with(".jpg") || lower.ends_with(".jpeg") { "image/jpeg".into() }
    else if lower.ends_with(".png") { "image/png".into() }
    else if lower.ends_with(".pdf") { "application/pdf".into() }
    else if lower.ends_with(".epub") { "application/epub+zip".into() }
    else if lower.ends_with(".txt") { "text/plain".into() }
    else { "application/octet-stream".into() }
}

fn uuid() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let t = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
    format!("{:x}", t)
}
