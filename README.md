# LocalSend MCP Server (`localsend-mcp`)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Runtime: Node.js 22+](https://img.shields.io/badge/Node.js-22%2B-green.svg)](https://nodejs.org)
[![Protocol: LocalSend v2.1](https://img.shields.io/badge/LocalSend-v2.1-emerald.svg)](https://localsend.org)

A high-performance, zero-external-dependency [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server that connects AI assistants (**Google Antigravity**, **Claude Desktop**, **Cursor**) directly to physical devices across your local Wi-Fi / LAN using the [LocalSend](https://localsend.org) protocol.

---

## ⚡ Key Capabilities

* **Zero-Cloud Local P2P Sharing**: Deliver generated artifacts, code files, research papers, and images directly to smartphones, tablets, and laptops over the local network.
* **Direct Text & Clipboard Push**: Send code snippets, terminal commands, or notes straight to target devices without writing temporary files to disk.
* **LAN Auto-Discovery**: Finds active LocalSend peers via UDP multicast (`224.0.0.167:53317`) or direct IP targets.
* **Desktop App Co-existence**: Runs a persistent listener on port `53318` so both the official LocalSend desktop application (`53317`) and this MCP server run seamlessly together on the same machine.
* **Clean LocalSend Favoriting**: Responds to `POST /api/localsend/v2/register` with `200 OK`, allowing you to add the agent to LocalSend's Favorites without connection errors.
* **In-Process X.509 Cryptography**: Generates TLS keys and ASN.1 DER certificates purely in-memory using Node.js crypto—**no external `openssl` binary required on Windows, Linux, or macOS**.

---

## 🛠️ MCP Tools Exposed

| Tool | Description |
| :--- | :--- |
| `localsend_devices` | Scans the Wi-Fi/LAN for online LocalSend peers, returning their alias, IP, port, and device model. |
| `localsend_send` | Sends files, directories, or direct text snippets to a peer by alias or IP. |
| `localsend_status` | Displays local network IPs, active listening port, fingerprint, and inbox statistics. |
| `localsend_history` | Lists files received into the agent's download directory. |
| `localsend_setup` | Configures the broadcast alias, auto-save directory, and transport protocol. |

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

## ⚙️ Configuration

### Antigravity (`mcp_servers` configuration)

Add `localsend-mcp` to your MCP configuration:

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

### 1. Discover Devices
```json
{
  "name": "localsend_devices",
  "arguments": {
    "timeoutSeconds": 3
  }
}
```

### 2. Send an Artifact / PDF to your Phone
```json
{
  "name": "localsend_send",
  "arguments": {
    "to": "Aaradhya's iPhone",
    "files": ["F:\\Aaradhya-Dev-Tamrakar\\brainstorm\\report\\main.pdf"]
  }
}
```

### 3. Send a Code Snippet / Text
```json
{
  "name": "localsend_send",
  "arguments": {
    "to": "SFG16",
    "text": "curl -s http://localhost:8000/health",
    "textFileName": "command.txt"
  }
}
```

---

## 🔒 Security & Privacy

* **100% Local**: No internet connection, cloud servers, or third-party relays are used. All network packets stay strictly within your local subnet.
* **Mutual TLS (mTLS)**: All transfers use TLS 1.3 encryption with client certificate presentation matching LocalSend v2 specification.
* **Path Traversal Protection**: Remote file names are sanitized to prevent directory traversal attacks.

---

## 📄 License

MIT © Aaradhya Dev Tamrakar