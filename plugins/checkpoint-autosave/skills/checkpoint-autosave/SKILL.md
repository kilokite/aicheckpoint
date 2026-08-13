---
name: checkpoint-autosave
description: Automatically create one immutable Checkpoint snapshot after every Codex coding turn that changes a Git worktree. Use for all implementation, bug-fix, refactor, formatting, or documentation tasks that may edit project files, and when the user asks about autosave history or recovery.
---

# Checkpoint Autosave

The plugin initializes autosave context when a Codex session starts. The model
creates one Checkpoint snapshot before finishing a turn that changed the
worktree, no matter how many edit tools ran during the turn.

## Requirements

- Keep the Checkpoint desktop app running.
- The project must be a Git repository with at least one commit.
- The local MCP endpoint is `http://127.0.0.1:47173/mcp`.

## Behavior

- After completing edits and verification, but before the final response, call
  `checkpoint_create_snapshot` exactly once with the repository root and title
  `Auto:<concise one-sentence Chinese summary of the changes>`.
- Do not edit files after creating the snapshot.
- Never delete, rename, restore, or otherwise mutate snapshots on the model's
  initiative.
- If the hook reports that Checkpoint is unavailable, tell the user to start
  the desktop app. Continue the coding task unless snapshot creation is an
  explicit prerequisite.
- To recover an earlier state, direct the user to the Checkpoint desktop UI;
  do not perform a restore through MCP.
