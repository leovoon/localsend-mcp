// Quick manual test harness: prints discovery results.
#[tokio::main]
async fn main() {
    let r = localsend_mcp_rust::discovery::scan(3000).await;
    println!("scan:\n{r}");
    let fa = localsend_mcp_rust::discovery::find_alias("Neon").await;
    println!("find_alias(Neon) = {fa:?}");
}
