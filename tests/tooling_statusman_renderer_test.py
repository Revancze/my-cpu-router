from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class StatusManRepository:
    def __init__(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name) / "repository"
        self.root.mkdir()

        self.environment = os.environ.copy()
        self.environment["NO_COLOR"] = "1"
        self.environment["PYTHONDONTWRITEBYTECODE"] = "1"
        self.environment["PYTHONPATH"] = str(self.root)

        self.bash = shutil.which("bash")
        if self.bash is None:
            raise unittest.SkipTest("bash is required")

        shutil.copytree(ROOT / "tools", self.root / "tools")

        self.git("init", "-b", "main")
        self.git("config", "user.name", "Codelaxy Test")
        self.git(
            "config",
            "user.email",
            "codelaxy-test@example.invalid",
        )
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.autocrlf", "false")

        self.write("tracked.txt", "committed\n")
        self.git("add", "--all")
        self.git("commit", "-m", "test fixture")

    def close(self) -> None:
        self.temporary_directory.cleanup()

    def write(self, relative_path: str, content: str) -> None:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content.encode("utf-8"))

    def git(
        self,
        *arguments: str,
        check: bool = True,
    ) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            ["git", *arguments],
            cwd=self.root,
            env=self.environment,
            check=check,
            capture_output=True,
        )

    def statusman(
        self,
        *arguments: str,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                self.bash,
                (
                    self.root
                    / "tools"
                    / "bin"
                    / "statusman"
                ).as_posix(),
                *arguments,
            ],
            cwd=self.root,
            env=self.environment,
            check=False,
            capture_output=True,
            text=True,
        )

    def human(self) -> str:
        result = self.statusman()

        if result.returncode != 0:
            raise AssertionError(result.stdout + result.stderr)

        self.assert_no_stderr(result)
        return result.stdout

    def snapshot(self) -> dict[str, object]:
        result = self.statusman("--json")

        if result.returncode != 0:
            raise AssertionError(result.stdout + result.stderr)

        self.assert_no_stderr(result)
        return json.loads(result.stdout)

    @staticmethod
    def assert_no_stderr(
        result: subprocess.CompletedProcess[str],
    ) -> None:
        if result.stderr:
            raise AssertionError(result.stderr)


class StatusManRendererTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repository = StatusManRepository()
        self.addCleanup(self.repository.close)

    def change_for(
        self,
        path: str,
    ) -> dict[str, object]:
        snapshot = self.repository.snapshot()

        changes = {
            change["path"]: change
            for change in snapshot["changes"]
        }

        self.assertIn(path, changes)
        return changes[path]

    def test_human_renderer_does_not_own_git_status_observation(
        self,
    ) -> None:
        content = (
            ROOT
            / "tools"
            / "statusman.sh"
        ).read_text(encoding="utf-8")

        self.assertNotIn("STATUS_FILE", content)
        self.assertNotIn("git status", content)
        self.assertIn("--statusman-facts", content)

    def test_clean_repository_agrees_with_snapshot(self) -> None:
        human = self.repository.human()
        snapshot = self.repository.snapshot()

        self.assertEqual(snapshot["changes"], [])
        self.assertIn("Working tree clean.", human)
        self.assertIn("SCORE 100", human)

    def test_unstaged_change_agrees_with_snapshot(self) -> None:
        self.repository.write(
            "tracked.txt",
            "unstaged\n",
        )

        change = self.change_for("tracked.txt")
        human = self.repository.human()

        self.assertEqual(change["index_status"], ".")
        self.assertEqual(change["worktree_status"], "M")
        self.assertIn("tracked.txt", human)
        self.assertIn("unstaged", human)
        self.assertIn("SCORE 90", human)

    def test_staged_change_agrees_with_snapshot(self) -> None:
        self.repository.write(
            "tracked.txt",
            "staged\n",
        )
        self.repository.git("add", "tracked.txt")

        change = self.change_for("tracked.txt")
        human = self.repository.human()

        self.assertEqual(change["index_status"], "M")
        self.assertEqual(change["worktree_status"], ".")
        self.assertIn("tracked.txt", human)
        self.assertIn("staged", human)
        self.assertIn("SCORE 100", human)

    def test_staged_and_unstaged_change_agrees_with_snapshot(
        self,
    ) -> None:
        self.repository.write(
            "tracked.txt",
            "staged\n",
        )
        self.repository.git("add", "tracked.txt")
        self.repository.write(
            "tracked.txt",
            "unstaged after staging\n",
        )

        change = self.change_for("tracked.txt")
        human = self.repository.human()

        self.assertEqual(change["index_status"], "M")
        self.assertEqual(change["worktree_status"], "M")
        self.assertIn("tracked.txt", human)
        self.assertIn("staged", human)
        self.assertIn("unstaged", human)
        self.assertIn("SCORE 90", human)

    def test_untracked_change_agrees_with_snapshot(self) -> None:
        self.repository.write(
            "new.txt",
            "untracked\n",
        )

        change = self.change_for("new.txt")
        human = self.repository.human()

        self.assertEqual(change["kind"], "untracked")
        self.assertEqual(change["index_status"], "?")
        self.assertEqual(change["worktree_status"], "?")
        self.assertIn("new.txt", human)
        self.assertIn("SCORE 95", human)

    def test_rename_and_delete_agree_with_snapshot(self) -> None:
        self.repository.write(
            "rename.txt",
            "rename\n",
        )
        self.repository.write(
            "delete.txt",
            "delete\n",
        )
        self.repository.git("add", "--all")
        self.repository.git("commit", "-m", "rename fixture")

        self.repository.git(
            "mv",
            "rename.txt",
            "renamed.txt",
        )
        self.repository.git(
            "rm",
            "delete.txt",
        )

        snapshot = self.repository.snapshot()
        human = self.repository.human()

        changes = {
            change["path"]: change
            for change in snapshot["changes"]
        }

        self.assertEqual(
            changes["renamed.txt"]["kind"],
            "rename",
        )
        self.assertEqual(
            changes["renamed.txt"]["original_path"],
            "rename.txt",
        )
        self.assertEqual(
            changes["delete.txt"]["index_status"],
            "D",
        )

        self.assertIn("rename.txt", human)
        self.assertIn("renamed.txt", human)
        self.assertIn("delete.txt", human)

    def test_conflict_agrees_with_snapshot(self) -> None:
        self.repository.git(
            "switch",
            "-c",
            "other",
        )
        self.repository.write(
            "tracked.txt",
            "other\n",
        )
        self.repository.git("add", "tracked.txt")
        self.repository.git(
            "commit",
            "-m",
            "other change",
        )

        self.repository.git("switch", "main")
        self.repository.write(
            "tracked.txt",
            "main\n",
        )
        self.repository.git("add", "tracked.txt")
        self.repository.git(
            "commit",
            "-m",
            "main change",
        )

        merge = self.repository.git(
            "merge",
            "other",
            check=False,
        )
        self.assertNotEqual(
            merge.returncode,
            0,
        )

        change = self.change_for("tracked.txt")
        human = self.repository.human()

        self.assertEqual(
            change["kind"],
            "unmerged",
        )
        self.assertIn("tracked.txt", human)
        self.assertIn(
            "Repository needs attention",
            human,
        )
        self.assertIn("SCORE 60", human)

    def test_statusman_facts_are_lf_only(self) -> None:
        self.repository.write(
            "tracked.txt",
            "modified\n",
        )

        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "tools.codelaxy.snapshot_cli",
                "--repository",
                str(self.repository.root),
                "--scope",
                "worktree",
                "--statusman-facts",
            ],
            cwd=self.repository.root,
            env=self.repository.environment,
            check=False,
            capture_output=True,
        )

        self.assertEqual(
            result.returncode,
            0,
            result.stdout + result.stderr,
        )
        self.assertNotIn(b"\r", result.stdout)
        self.assertIn(b"UNSTAGED\t1\n", result.stdout)


if __name__ == "__main__":
    unittest.main()
