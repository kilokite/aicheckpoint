import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import checkpoint_after_edit as hook


class CheckpointAfterEditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "repository"
        self.data = Path(self.temporary.name) / "data"
        self.root.mkdir()
        self.git("init")
        self.git("config", "user.name", "Checkpoint Test")
        self.git("config", "user.email", "checkpoint@example.test")
        self.git("config", "core.autocrlf", "false")
        (self.root / "tracked.txt").write_text("base\n", encoding="utf-8")
        self.git("add", ".")
        self.git("commit", "-m", "base")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def git(self, *args: str) -> None:
        subprocess.run(
            ["git", "-C", str(self.root), *args],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def invoke(self, baseline: bool) -> str:
        payload = json.dumps(
            {
                "cwd": str(self.root),
                "hook_event_name": "SessionStart" if baseline else "Stop",
            }
        )
        argv = ["checkpoint_after_edit.py"] + (["--baseline"] if baseline else [])
        output = io.StringIO()
        with (
            mock.patch.dict(os.environ, {"PLUGIN_DATA": str(self.data)}),
            mock.patch("sys.stdin", io.StringIO(payload)),
            mock.patch("sys.stdout", output),
            mock.patch("sys.argv", argv),
        ):
            self.assertEqual(hook.main(), 0)
        return output.getvalue()

    def test_only_snapshots_changed_content(self) -> None:
        baseline = json.loads(self.invoke(baseline=True))
        self.assertIn(
            "Checkpoint autosave is active",
            baseline["hookSpecificOutput"]["additionalContext"],
        )
        self.assertEqual(self.invoke(baseline=False), "")

        (self.root / "tracked.txt").write_text("changed\n", encoding="utf-8")
        with mock.patch.object(hook, "latest_snapshot_matches", return_value=False):
            result = json.loads(self.invoke(baseline=False))
        self.assertEqual(result["decision"], "block")
        self.assertIn("Auto:<one-sentence summary", result["reason"])

        with mock.patch.object(hook, "latest_snapshot_matches", return_value=True):
            self.assertEqual(self.invoke(baseline=False), "")
        self.assertEqual(self.invoke(baseline=False), "")

    def test_untracked_content_changes_fingerprint(self) -> None:
        before = hook.worktree_state(self.root)
        (self.root / "new.txt").write_text("new\n", encoding="utf-8")
        after = hook.worktree_state(self.root)
        self.assertNotEqual(before, after)


if __name__ == "__main__":
    unittest.main()
