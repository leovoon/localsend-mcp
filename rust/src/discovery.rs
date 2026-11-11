use std::collections::HashMap;
use std::fmt::Write as _;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

use axum::{
    Router,
    extract::{ConnectInfo, State, Json},
    routing::post,
};
use localsend::models::device::DeviceInfo;
use serde_json::json;
use tokio::net::{TcpListener, UdpSocket};
use tokio::sync::Mutex;

const MULTICAST_ADDR: Ipv4Addr = Ipv4Addr::new(224, 0, 0, 167);
const PEER_PORT: u16 = 53317;
const OUR_FINGERPRINT: &str = "rust-mcp";
const CACHE_TTL: Duration = Duration::from_secs(20);

#[derive(Clone, Debug)]
pub struct Peer {
    pub alias: String,
    pub ip: String,
    pub port: u16,
    pub model: String,
}

// ---------------------------------------------------------------------------
// Passive HTTP registration listener (peers POST their DeviceInfo here after
// receiving our announce). Plain HTTP — so we advertise protocol "http".
// ---------------------------------------------------------------------------

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

async fn serve_register_listener(peers: Arc<Mutex<HashMap<String, DeviceInfo>>>) -> u16 {
    let listener = match TcpListener::bind("0.0.0.0:0").await {
        Ok(l) => l,
        Err(_) => return 0,
    };
    let port = listener.local_addr().map(|a| a.port()).unwrap_or(0);
    let app = Router::new()
        .route("/api/localsend/v2/register", post(register_handler))
        .route("/api/localsend/v3/register", post(register_handler))
        .with_state(AppState { peers })
        .into_make_service_with_connect_info::<SocketAddr>();
    tokio::spawn(async move {
        let _ = axum::serve(listener, app).await;
    });
    port
}

fn our_info(port: u16) -> serde_json::Value {
    json!({
        "alias": "localsend-mcp-rust",
        "version": "2.1",
        "deviceModel": "Mac",
        "deviceType": "desktop",
        "fingerprint": OUR_FINGERPRINT,
        "port": port,
        "protocol": "http",
        "download": true,
        "announce": true
    })
}

// ---------------------------------------------------------------------------
// Active UDP probe: multicast + subnet broadcast announce, then collect
// unicast replies that peers send straight back to our socket.
// ---------------------------------------------------------------------------

async fn probe_udp(peers: &Arc<Mutex<HashMap<String, DeviceInfo>>>, port: u16, timeout_ms: u64) {
    let udp = match UdpSocket::bind("0.0.0.0:0").await {
        Ok(s) => s,
        Err(_) => return,
    };
    let _ = udp.set_broadcast(true);
    let msg = our_info(port).to_string();
    let bytes = msg.as_bytes();

    let targets = [
        SocketAddrV4::new(MULTICAST_ADDR, PEER_PORT),
        SocketAddrV4::new(Ipv4Addr::new(255, 255, 255, 255), PEER_PORT),
    ];
    for t in targets {
        let _ = udp.send_to(bytes, t).await;
    }

    let deadline = tokio::time::Instant::now() + Duration::from_millis(timeout_ms.max(300));
    let mut buf = [0u8; 8192];
    while tokio::time::Instant::now() < deadline {
        let r = tokio::time::timeout_at(deadline, udp.recv_from(&mut buf)).await;
        match r {
            Ok(Ok((n, src))) => {
                if !src.ip().is_multicast() {
                    if let Ok(dev) = serde_json::from_slice::<DeviceInfo>(&buf[..n]) {
                        if dev.fingerprint != OUR_FINGERPRINT {
                            peers.lock().await.insert(src.ip().to_string(), dev);
                        }
                    }
                }
            }
            _ => break,
        }
    }
}

// ---------------------------------------------------------------------------
// mDNS: browse _localsend._tcp, resolve each instance to host:port, then host
// to IPv4. This mirrors exactly what official LocalSend apps use for discovery.
// ---------------------------------------------------------------------------

async fn mdns_browse() -> Vec<String> {
    let Ok(out) = tokio::time::timeout(
        Duration::from_secs(3),
        tokio::process::Command::new("dns-sd")
            .args(["-B", "_localsend._tcp", "local."])
            .kill_on_drop(true)
            .output(),
    )
    .await
    else {
        return Vec::new();
    };
    let Ok(out) = out else { return Vec::new() };
    let text = String::from_utf8_lossy(&out.stdout);
    let mut instances = Vec::new();
    for line in text.lines() {
        if line.trim().is_empty() || line.contains("Timestamp") || line.starts_with("DATE:") {
            continue;
        }
        let toks: Vec<&str> = line.split_whitespace().collect();
        // Instance name is everything after the service type token.
        if let Some(pos) = toks.iter().position(|t| *t == "_localsend._tcp.") {
            let rest = &toks[pos + 1..];
            if !rest.is_empty() {
                instances.push(rest.join(" "));
            }
        } else if let Some(pos) = toks.iter().position(|t| t.ends_with("._tcp.")) {
            let rest = &toks[pos + 1..];
            if !rest.is_empty() {
                instances.push(rest.join(" "));
            }
        }
    }
    instances
}

async fn mdns_resolve(instance: &str) -> Option<(String, u16)> {
    let out = tokio::time::timeout(
        Duration::from_secs(3),
        tokio::process::Command::new("dns-sd")
            .args(["-L", instance, "_localsend._tcp", "local."])
            .kill_on_drop(true)
            .output(),
    )
    .await
    .ok()?
    .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let mut host: Option<String> = None;
    let mut port: Option<u16> = None;
    for line in text.lines() {
        for tok in line.split_whitespace() {
            let t = tok.trim_end_matches('.');
            if t.ends_with(".local") || t.ends_with(".local.") {
                if host.is_none() && !t.starts_with("local") {
                    host = Some(tok.to_string());
                }
            } else if let Ok(p) = tok.parse::<u16>() {
                if port.is_none() && p > 0 {
                    port = Some(p);
                }
            }
        }
    }
    host.map(|h| (h, port.unwrap_or(PEER_PORT)))
}

async fn mdns_ipv4(host: &str) -> Option<String> {
    let out = tokio::time::timeout(
        Duration::from_secs(3),
        tokio::process::Command::new("dns-sd")
            .args(["-G", "v4", host])
            .kill_on_drop(true)
            .output(),
    )
    .await
    .ok()?
    .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    text.split_whitespace()
        .find_map(|t| t.parse::<Ipv4Addr>().ok().map(|a| a.to_string()))
}

async fn mdns_discover() -> Vec<Peer> {
    let mut peers = Vec::new();
    let instances = mdns_browse().await;
    for inst in instances {
        let Some((host, port)) = mdns_resolve(&inst).await else { continue };
        let ip = mdns_ipv4(&host).await;
        let ip = ip.unwrap_or(host.trim_end_matches('.').to_string());
        peers.push(Peer {
            alias: inst,
            ip,
            port,
            model: "mDNS".to_string(),
        });
    }
    peers
}

// ---------------------------------------------------------------------------
// Cache (mDNS + UFO scans are slow; don't repeat within TTL)
// ---------------------------------------------------------------------------

static CACHE: OnceLock<Mutex<Option<(Instant, Vec<Peer>)>>> = OnceLock::new();

fn cache() -> &'static Mutex<Option<(Instant, Vec<Peer>)>> {
    CACHE.get_or_init(|| Mutex::new(None))
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

fn merge_peers(udp: HashMap<String, DeviceInfo>, mdns: Vec<Peer>) -> Vec<Peer> {
    let mut map: HashMap<String, Peer> = HashMap::new();
    for (ip, dev) in udp {
        map.insert(ip.clone(), Peer {
            alias: dev.alias,
            ip,
            port: dev.port,
            model: dev.device_model.unwrap_or_default(),
        });
    }
    for p in mdns {
        map.entry(p.ip.clone()).or_insert(p);
    }
    let mut v: Vec<Peer> = map.into_values().collect();
    v.sort_by(|a, b| a.alias.to_lowercase().cmp(&b.alias.to_lowercase()));
    v
}

pub async fn collect_peers(timeout_ms: u64) -> Vec<Peer> {
    {
        let guard = cache().lock().await;
        if let Some((t, cached)) = guard.as_ref() {
            if t.elapsed() < CACHE_TTL && !cached.is_empty() {
                return cached.clone();
            }
        }
    }

    let udp_peers: Arc<Mutex<HashMap<String, DeviceInfo>>> =
        Arc::new(Mutex::new(HashMap::new()));
    let listener_port = serve_register_listener(udp_peers.clone()).await;

    let u = probe_udp(&udp_peers, listener_port.max(1), timeout_ms);
    let m = mdns_discover();
    let (_, mdns_peers) = tokio::join!(u, m);

    let udp_map = udp_peers.lock().await.clone();
    let merged = merge_peers(udp_map, mdns_peers);

    {
        let mut c = cache().lock().await;
        *c = Some((Instant::now(), merged.clone()));
    }
    merged
}

pub async fn find_alias(alias: &str) -> Option<Peer> {
    let lower = alias.to_lowercase();
    let peers = collect_peers(2500).await;
    peers.into_iter().find(|p| {
        let a = p.alias.to_lowercase();
        a == lower || a.contains(&lower)
    })
}

pub async fn scan(timeout_ms: u64) -> String {
    let peers = collect_peers(timeout_ms).await;
    if peers.is_empty() {
        return "no devices found".to_string();
    }
    let mut out = String::new();
    for p in &peers {
        let _ = writeln!(out, "{}\t{}:{}\t({})", p.alias, p.ip, p.port, p.model);
    }
    out.trim_end().to_string()
}
