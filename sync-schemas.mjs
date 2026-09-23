import fs from "fs";
import path from "path";
import { TOOLS } from "./dist/tools.js";

const targetDir = "C:/Users/Aaradhya/.gemini/antigravity/mcp/localsend";
if (!fs.existsSync(targetDir)) {
  fs.mkdirSync(targetDir, { recursive: true });
}

for (const t of TOOLS) {
  const schema = {
    name: t.name,
    description: t.description,
    parameters: t.inputSchema
  };
  const filePath = path.join(targetDir, `${t.name}.json`);
  fs.writeFileSync(filePath, JSON.stringify(schema, null, 2), "utf8");
  console.log(`Wrote schema: ${filePath}`);
}

console.log("LocalSend MCP schemas successfully synced!");
