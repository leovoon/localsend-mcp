# LocalSend MCP Server (`localsend-mcp`)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Runtime: Node.js 22+](https://img.shields.io/badge/Node.js-22%2B-green.svg)](https://nodejs.org)
[![Protocol: LocalSend v2.1](https://img.shields.io/badge/LocalSend-v2.1-emerald.svg)](https://localsend.org)

A high-performance, zero-external-dependency [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server that connects AI assistants (**Google Antigravity**, **Claude Desktop**, **Cursor**) directly to physical devices across your local Wi-Fi / LAN using the [LocalSend](https://localsend.org) protocol.

---

## ⚡ Key Capabilities

* **Bidirectional Local P2P Sharing**:
  * **Outbound (AI Agent $\rightarrow$ Device)**: Deliver generated artifacts, code files, research papers, and images directly to smartphones, tablets, and laptops.
  * **Inbound (Device $\rightarrow$ AI Agent)**: Send photos, voice memos, logs, or documents from your phone directly into the agent's download folder.
* **Direct Text & Clipboard Push**: Send code snippets, terminal commands, or notes straight to target devices without writing temporary files to disk.
* **LAN Auto-Discovery**: Finds active LocalSend peers via UDP multicast (`224.0.0.167:53317`) and catches HTTP registration handshakes.
* **Desktop App Co-existence**: Runs a persistent background listener on port `53318` so both the official LocalSend desktop application (`53317`) and this MCP server run seamlessly together on the same machine.
* **Clean LocalSend Favoriting**: Actively responds to `POST /api/localsend/v2/register` with `200 OK`, allowing mobile and desktop LocalSend apps to favorite/star the agent without connection errors.
* **In-Process X.509 Cryptography**: Generates TLS keys and ASN.1 DER certificates purely in-memory using Node.js crypto—**no external `openssl` binary required on Windows, Linux, or macOS**.

---

## 🛠️ MCP Tools Exposed

| Tool | Parameters | Description |
| :--- | :--- | :--- |
| `localsend_devices` | `timeoutSeconds` (opt) | Scans the Wi-Fi/LAN for online LocalSend peers, returning their alias, IP, port, and device model. |
| `localsend_send` | `to` (req), `files` (opt), `text` (opt), `pin` (opt) | Sends files, directories, or direct text snippets to a peer by alias or IP. |
| `localsend_status` | none | Displays local network IPs, active listening port, fingerprint, and inbox statistics. |
| `localsend_history` | none | Lists files received into the agent's download directory. |
| `localsend_setup` | `alias` (opt), `downloadDir` (opt) | Configures the broadcast alias, auto-save directory, and transport protocol. |

---

## 🚀 Installation & Build

```powershell
cd F:\Aaradhya-Dev-Tamrakar\localsend-mcp

# Install dependencies
npm install

# Compile TypeScript to dist/
npm run build
```

---

## 🔄 Automated Git Synchronization (`sync.ps1`)

The repository includes a dedicated PowerShell synchronization script that enforces pre-commit secret scans, automatically recompiles TypeScript when source files change, and formats conventional commits:

```powershell
# Routine build, commit, and push
.\sync.ps1

# Custom commit message
.\sync.ps1 -m "feat(localsend): add automatic clipboard sync"

# Safe rebase pull only
.\sync.ps1 -PullOnly

# Dry-run mode (preview without changing git state)
.\sync.ps1 -WhatIf
```

---

## ⚙️ Configuration

### Antigravity (`mcp_servers` configuration)

Add `localsend-mcp` to your Antigravity MCP settings:

```json
{
  "mcpServers": {
    "localsend": {
      "command": "node",
      "args": ["F:\\Aaradhya-Dev-Tamrakar\\localsend-mcp\\dist\\index.js"]
    }
  }
}
```

### Claude Desktop (`claude_desktop_config.json`)

```json
{
  "mcpServers": {
    "localsend": {
      "command": "node",
      "args": ["F:\\Aaradhya-Dev-Tamrakar\\localsend-mcp\\dist\\index.js"]
    }
  }
}
```

---

## 🧪 Usage Examples

### 1. Discover Devices on LAN
```json
{
  "name": "localsend_devices",
  "arguments": {
    "timeoutSeconds": 3
  }
}
```

### 2. Send an Artifact or Report to Your Phone
```json
{
  "name": "localsend_send",
  "arguments": {
    "to": "V2029",
    "files": ["F:\\Aaradhya-Dev-Tamrakar\\brainstorm\\report\\main.pdf"]
  }
}
```

### 3. Push a Code Snippet Directly to Clipboard
```json
{
  "name": "localsend_send",
  "arguments": {
    "to": "SFG16",
    "text": "Get-Process localsend_app | Select-Object Id, ProcessName",
    "textFileName": "inspect.ps1"
  }
}
```

### 4. Check Inbox for Files Sent From Mobile
```json
{
  "name": "localsend_history",
  "arguments": {}
}
```

---

## 🔒 Security & Privacy

* **100% Local**: No internet connection, cloud servers, or third-party relays are used. All network packets stay strictly within your local subnet.
* **Mutual TLS (mTLS)**: All transfers use TLS encryption with client certificate presentation matching the LocalSend v2 specification.
* **Path Traversal Protection**: Remote file names are sanitized to prevent directory traversal attacks.

---

## 📄 License

MIT © Aaradhya Dev Tamrakar