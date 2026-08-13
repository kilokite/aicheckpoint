import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const MCP_URL = "http://127.0.0.1:47173/mcp";
const MCP_PROTOCOL_VERSION = "2025-06-18";

const AUTOSAVE_CONTEXT =
  "Checkpoint autosave is active. For every conversation turn that changes " +
  "the Git worktree, after verification and before the final response, call " +
  "the checkpoint_create_snapshot tool exactly once. Use the repository " +
  "root as project_path and title it Auto:<concise one-sentence Chinese " +
  "summary>. Do not edit files after creating it. Unless the user explicitly " +
  "asks, never create a Git commit.";

export default function checkpointAutosave(pi: ExtensionAPI): void {
  pi.on("before_agent_start", async (event) => ({
    systemPrompt: `${event.systemPrompt}\n\n${AUTOSAVE_CONTEXT}`,
  }));

  pi.registerTool({
    name: "checkpoint_create_snapshot",
    label: "Create Checkpoint",
    description:
      "为指定 Git 项目创建一个不会移动 HEAD、分支或 stash 的 Checkpoint 快照。",
    parameters: Type.Object({
      project_path: Type.String({
        description: "Git 项目的绝对路径。",
      }),
      title: Type.Optional(
        Type.String({
          description: "快照名称，格式建议为 Auto:<一句中文总结>。",
        }),
      ),
    }),
    async execute(_toolCallId, params) {
      try {
        const initialized = await postMcp({
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: {
            protocolVersion: MCP_PROTOCOL_VERSION,
            capabilities: {},
            clientInfo: { name: "pi-checkpoint-autosave", version: "1.0.0" },
          },
        });
        const sessionId = initialized.sessionId;
        if (!sessionId) throw new Error("Checkpoint MCP 未返回会话 ID");

        await postMcp(
          { jsonrpc: "2.0", method: "notifications/initialized" },
          sessionId,
        );
        const response = await postMcp(
          {
            jsonrpc: "2.0",
            id: 2,
            method: "tools/call",
            params: {
              name: "checkpoint_create_snapshot",
              arguments: {
                project_path: params.project_path,
                title: params.title,
              },
            },
          },
          sessionId,
        );
        const result = (response.payload.result ?? {}) as Record<string, unknown>;
        if (response.payload.error || result.isError === true) {
          throw new Error(extractMcpText(result) || "Checkpoint 快照创建失败");
        }
        return {
          content: [
            { type: "text", text: extractMcpText(result) || "Checkpoint 快照已创建。" },
          ],
          details: result.structuredContent ?? {},
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Checkpoint 快照失败：${String(error)}` }],
          details: {},
          isError: true,
        };
      }
    },
  });
}

async function postMcp(
  body: Record<string, unknown>,
  sessionId?: string,
): Promise<{ payload: Record<string, unknown>; sessionId?: string }> {
  const headers: Record<string, string> = {
    Accept: "application/json, text/event-stream",
    "Content-Type": "application/json",
    "MCP-Protocol-Version": MCP_PROTOCOL_VERSION,
  };
  if (sessionId) headers["mcp-session-id"] = sessionId;
  const response = await fetch(MCP_URL, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  const text = await response.text();
  const payload = text ? (JSON.parse(text) as Record<string, unknown>) : {};
  if (!response.ok) throw new Error(`Checkpoint MCP 返回 HTTP ${response.status}`);
  return {
    payload,
    sessionId: response.headers.get("mcp-session-id") ?? sessionId,
  };
}

function extractMcpText(result: Record<string, unknown>): string {
  const content = Array.isArray(result.content) ? result.content : [];
  return content
    .map((item) => (item as Record<string, unknown>).text)
    .filter((item): item is string => typeof item === "string")
    .join(" ");
}
