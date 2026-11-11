mod discovery;
mod send;

use rmcp::{
    ServerHandler,
    handler::server::tool::ToolCallContext,
    model::{
        CallToolRequestParam, CallToolResult, ListToolsResult, PaginatedRequestParam,
        ServerCapabilities, ServerInfo,
    },
    tool,
    model::Tool,
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
        discovery::scan(3000).await
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
                Tool::new(
                    "localsend_send",
                    "Send files/text to a LocalSend device by alias or IP",
                    serde_json::json!({
                        "type":"object",
                        "properties":{
                            "to":{"type":"string"},
                            "files":{"type":"array","items":{"type":"string"}},
                            "text":{"type":"string"}
                        },
                        "required":["to"]
                    }).as_object().cloned().unwrap(),
                ),
            ],
            next_cursor: None,
        })
    }

    async fn call_tool(
        &self,
        request: CallToolRequestParam,
        context: rmcp::service::RequestContext<rmcp::RoleServer>,
    ) -> Result<CallToolResult, rmcp::Error> {
        let tool_name = request.name.clone();
        let args = request.arguments.clone();
        let res = match tool_name.as_ref() {
            "localsend_status" => {
                let r = self.localsend_status().await;
                rmcp::model::CallToolResult::success(vec![rmcp::model::Content::text(r)])
            }
            "localsend_devices" => {
                let r = self.localsend_devices().await;
                rmcp::model::CallToolResult::success(vec![rmcp::model::Content::text(r)])
            }
            "localsend_send" => {
                let to = args.as_ref().and_then(|a| a.get("to")).and_then(|v| v.as_str()).unwrap_or("").to_string();
                let files = args.as_ref().and_then(|a| a.get("files")).and_then(|v| v.as_array()).map(|a| a.iter().filter_map(|x| x.as_str().map(|s| s.to_string())).collect()).unwrap_or_default();
                let text = args.as_ref().and_then(|a| a.get("text")).and_then(|v| v.as_str()).map(|s| s.to_string());
                let r = send::send(to, files, text).await;
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
