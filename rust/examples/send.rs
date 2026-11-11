// Manual test: send a text note to a device by alias.
#[tokio::main]
async fn main() {
    let alias = std::env::args().nth(1).unwrap_or_else(|| "MyDevice".to_string());
    let r = localsend_mcp_rust::send::send(
        alias,
        Vec::new(),
        Some("test from localsend-mcp rust".to_string()),
    )
    .await;
    println!("{r}");
}
