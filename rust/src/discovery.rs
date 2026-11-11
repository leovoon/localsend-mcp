use std::collections::HashMap;
use std::fmt::Write as _;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};
use std::sync::Arc;
use std::time::Duration;

use axum::{
    Router,
    extract::{ConnectInfo, State, Json},
    routing::post,
};
use localsend::models::device::DeviceInfo;
use serde_json::json;
use tokio::net::{TcpListener, UdpSocket};
use tokio::sync::Mutex;

#[derive(Clone)]
struct AppState {
    peers: Arc<Mutex<HashMap<String, DeviceInfo>>>,
}

async fn register_handler(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(dev): Json<DeviceInfo>,
) -> axum::http::StatusCode {
    state.peers.lock().await.insert(addr.ip().to_string(), dev);
    axum::http::StatusCode::OK
}

pub async fn scan(timeout_ms: u64) -> String {
    eprintln!("scan start");
    let peers: Arc<Mutex<HashMap<String, DeviceInfo>>> = Arc::new(Mutex::new(HashMap::new()));
    let state = AppState { peers: peers.clone() };

    // Bind HTTP server on ephemeral port
    eprintln!("binding");
    let listener = match TcpListener::bind("0.0.0.0:0").await {
        Ok(l) => l,
        Err(e) => return format!("bind error: {e}"),
    };
    let port = listener.local_addr().map(|a| a.port()).unwrap_or(0);
    eprintln!("port {}", port);

    let app = Router::new()
        .route("/api/localsend/v2/register", post(register_handler))
        .route("/api/localsend/v3/register", post(register_handler))
        .with_state(state)
        .into_make_service_with_connect_info::<SocketAddr>();

    eprintln!("spawning server");
    let server_handle = tokio::spawn(async move {
        let _ = axum::serve(listener, app).await;
    });
    eprintln!("server spawned");

    eprintln!("sending multicast");
    let _ = tokio::task::spawn_blocking(move || {
        use std::net::UdpSocket as StdUdp;
        if let Ok(sock) = StdUdp::bind("0.0.0.0:0") {
            let msg = json!({
                "alias": "localsend-mcp-rust",
                "version": "2.1",
                "deviceModel": "Mac",
                "deviceType": "desktop",
                "fingerprint": "rust-mcp",
                "port": port,
                "protocol": "https",
                "download": true,
                "announce": true
            });
            let bytes = msg.to_string().into_bytes();
            let addr = SocketAddrV4::new(Ipv4Addr::new(224, 0, 0, 167), 53317);
            let _ = sock.send_to(&bytes, addr);
            eprintln!("sent (blocking)");
        }
    });

    let _ = tokio::task::spawn_blocking(move || { std::thread::sleep(std::time::Duration::from_millis(timeout_ms)); }).await;

    let peers = peers.lock().await;
    let mut out = String::new();
    for (ip, p) in peers.iter() {
        let _ = writeln!(out, "{} {}:{} (port {})", p.alias, ip, p.port, p.port);
    }
    server_handle.abort();
    if out.trim().is_empty() { "no devices found".to_string() } else { out }
}

