#!/usr/bin/env python3
"""Ask Codex to create a Checkpoint snapshot when a turn changed a worktree."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from urllib import request


MCP_URL = "http://127.0.0.1:47173/mcp"
PROTOCOL_VERSION = "2025-06-18"


def run_git(root: Path, *args: str) -> bytes:
    completed = subprocess.run(
        ["git", "-C", str(root), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=True,
    )
    return completed.stdout


def run_git_with_index(root: Path, index: Path, *args: str) -> bytes:
    environment = os.environ.copy()
    environment["GIT_INDEX_FILE"] = str(index)
    completed = subprocess.run(
        ["git", "-C", str(root), *args],
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=True,
    )
    return completed.stdout


def repository_root(cwd: str) -> Path | None:
    try:
        completed = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=True,
            text=True,
        )
        root = completed.stdout.strip()
        run_git(Path(root), "rev-parse", "--verify", "HEAD")
        return Path(root)
    except (OSError, subprocess.CalledProcessError):
        return None


def worktree_state(root: Path) -> dict[str, dict[str, str]]:
    files: dict[str, dict[str, str]] = {}
    tracked = run_git(root, "diff", "--name-only", "-z", "HEAD", "--").split(b"\0")
    for raw_path in sorted(path for path in tracked if path):
        path = raw_path.decode("utf-8", errors="surrogateescape")
        patch = run_git(root, "diff", "--binary", "--no-ext-diff", "HEAD", "--", path)
        files[path] = {
            "kind": "modified" if (root / path).exists() else "deleted",
            "signature": hashlib.sha256(patch).hexdigest(),
        }
    untracked = run_git(
        root,
        "ls-files",
        "--others",
        "--exclude-standard",
        "-z",
    ).split(b"\0")
    for raw_path in sorted(path for path in untracked if path):
        path = raw_path.decode("utf-8", errors="surrogateescape")
        files[path] = {
            "kind": "untracked",
            "signature": run_git(root, "hash-object", "--", path).decode().strip(),
        }
    return files


def state_path(root: Path) -> Path:
    data_root = os.environ.get("PLUGIN_DATA")
    if data_root:
        directory = Path(data_root) / "worktrees"
    else:
        directory = Path.home() / ".codex" / "plugin-data" / "checkpoint-autosave"
    directory.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(os.path.normcase(str(root)).encode("utf-8")).hexdigest()
    return directory / f"{key}.json"


def read_previous_fingerprint(path: Path) -> str | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        return payload.get("fingerprint")
    except (OSError, ValueError, TypeError):
        return None


def write_state(
    path: Path,
    root: Path,
    fingerprint: str,
    files: dict[str, dict[str, str]],
) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(
            {
                "repository": str(root),
                "fingerprint": fingerprint,
                "files": files,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    os.replace(temporary, path)


def post_json(payload: dict, session_id: str | None = None) -> tuple[dict, str | None]:
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "MCP-Protocol-Version": PROTOCOL_VERSION,
    }
    if session_id:
        headers["mcp-session-id"] = session_id
    http_request = request.Request(
        MCP_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with request.urlopen(http_request, timeout=8) as response:
        body = response.read()
        return (json.loads(body) if body else {}), response.headers.get(
            "mcp-session-id"
        )


def latest_snapshot_hash(root: Path) -> str | None:
    initialized, session_id = post_json(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {
                    "name": "checkpoint-autosave-hook",
                    "version": "1.0.0",
                },
            },
        }
    )
    if "error" in initialized or not session_id:
        return None
    post_json(
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        session_id,
    )
    response, _ = post_json(
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {
                "name": "checkpoint_get_latest_snapshot",
                "arguments": {"project_path": str(root)},
            },
        },
        session_id,
    )
    structured = response.get("result", {}).get("structuredContent", {})
    return structured.get("hash") if structured.get("found") else None


def current_worktree_tree(root: Path) -> str:
    index_path = Path(
        run_git(
            root,
            "rev-parse",
            "--path-format=absolute",
            "--git-path",
            "index",
        )
        .decode()
        .strip()
    )
    with tempfile.TemporaryDirectory(prefix="checkpoint_hook_") as directory:
        temporary_index = Path(directory) / "index"
        if index_path.exists():
            shutil.copy2(index_path, temporary_index)
        else:
            run_git_with_index(root, temporary_index, "read-tree", "HEAD")
        run_git_with_index(root, temporary_index, "add", "-A", "--", ".")
        return run_git_with_index(root, temporary_index, "write-tree").decode().strip()


def latest_snapshot_matches(root: Path) -> bool:
    snapshot_hash = latest_snapshot_hash(root)
    if not snapshot_hash:
        return False
    snapshot_tree = run_git(root, "rev-parse", f"{snapshot_hash}^{{tree}}").decode().strip()
    return snapshot_tree == current_worktree_tree(root)


def session_context() -> None:
    context = (
        "Checkpoint autosave is active. For every conversation turn that changes "
        "the Git worktree, after verification and before the final response, call "
        "checkpoint_create_snapshot exactly once. Use the repository root as "
        "project_path and title it Auto:<concise one-sentence Chinese summary>. "
        "Do not edit files after creating it."
    )
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": context,
                }
            },
            ensure_ascii=False,
        )
    )


def request_ai_snapshot(root: Path) -> None:
    reason = (
        "This conversation changed the Git worktree. Before finishing, call "
        "the checkpoint_create_snapshot MCP tool exactly once with "
        f"project_path={root} and a concise Chinese title in the form "
        "Auto:<one-sentence summary of what you changed>. Do not edit files "
        "after creating the snapshot, then finish the response."
    )
    print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))


def main() -> int:
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return 0

    root = repository_root(str(hook_input.get("cwd") or os.getcwd()))
    if root is None:
        return 0
    try:
        files = worktree_state(root)
        fingerprint = hashlib.sha256(
            json.dumps(files, sort_keys=True, ensure_ascii=False).encode("utf-8")
        ).hexdigest()
    except (OSError, subprocess.CalledProcessError):
        return 0

    path = state_path(root)
    if "--baseline" in sys.argv:
        write_state(path, root, fingerprint, files)
        session_context()
        return 0
    if read_previous_fingerprint(path) == fingerprint:
        return 0

    try:
        if latest_snapshot_matches(root):
            write_state(path, root, fingerprint, files)
            return 0
    except (OSError, ValueError, subprocess.CalledProcessError):
        pass
    request_ai_snapshot(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
