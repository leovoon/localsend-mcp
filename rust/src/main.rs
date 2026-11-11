use rmcp::{
    ServerHandler,
    handler::server::tool::ToolCallContext,
    model::{
        CallToolRequestParam, CallToolResult, ListToolsResult, PaginatedRequestParam,
        ServerCapabilities, ServerInfo,
    },
    schemars, tool,
};
use rmcp::ServiceExt;

#[derive(Debug, Clone, Default)]
pub struct LocalSendMcp;

impl LocalSendMcp {
    #[tool(description = "Show local network/config info")]
    pub async fn localsend_status(&self) -> String {
        "download_dir=/Users/leovoon/Downloads".to_string()
    }

    #[tool(description = "Scan LAN for LocalSend peers")]
    pub async fn localsend_devices(&self) -> String {
        // The localsend crate binds UDP 53317 directly and panics when the
        // port is already in use (e.g. by the desktop LocalSend app), so it
        // cannot coexist. Discovery needs a reimplementation using an
        // ephemeral receiver port; pending.
        "discovery not yet available in Rust build (port 53317 in use)".to_string()
    }
}

impl ServerHandler for LocalSendMcp {
    async fn list_tools(
        &self,
        _request: PaginatedRequestParam,
        _context: rmcp::service::RequestContext<rmcp::RoleServer>,
    ) -> Result<ListToolsResult, rmcp::Error> {
        Ok(ListToolsResult {
            tools: vec![
                LocalSendMcp::localsend_status_tool_attr(),
                LocalSendMcp::localsend_devices_tool_attr(),
            ],
            next_cursor: None,
        })
    }

    async fn call_tool(
        &self,
        request: CallToolRequestParam,
        context: rmcp::service::RequestContext<rmcp::RoleServer>,
    ) -> Result<CallToolResult, rmcp::Error> {
        let tcc = ToolCallContext::new(self, request, context);
        let res = match tcc.name() {
            "localsend_status" => {
                let r = self.localsend_status().await;
                rmcp::model::CallToolResult::success(vec![rmcp::model::Content::text(r)])
            }
            "localsend_devices" => {
                let r = self.localsend_devices().await;
                rmcp::model::CallToolResult::success(vec![rmcp::model::Content::text(r)])
            }
            _ => return Err(rmcp::Error::invalid_params("method not found", None)),
        };
        Ok(res)
    }

    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            instructions: Some("LocalSend MCP (Rust)".into()),
            capabilities: ServerCapabilities::builder().enable_tools().build(),
            ..Default::default()
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let service = LocalSendMcp.serve(rmcp::transport::stdio()).await?;
    service.waiting().await?;
    Ok(())
}
