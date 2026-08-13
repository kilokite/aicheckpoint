import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const AUTOSAVE_CONTEXT =
  "Checkpoint autosave is active. For every conversation turn that changes " +
  "the Git worktree, after verification and before the final response, call " +
  "the checkpoint_create_snapshot MCP tool exactly once. Use the repository " +
  "root as project_path and title it Auto:<concise one-sentence Chinese " +
  "summary>. Do not edit files after creating it.";

export default function checkpointAutosave(pi: ExtensionAPI): void {
  pi.on("before_agent_start", async (event) => ({
    systemPrompt: `${event.systemPrompt}\n\n${AUTOSAVE_CONTEXT}`,
  }));
}
