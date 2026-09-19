from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.codelaxy import GitSnapshotError, decode_record, observe_snapshot


class GitRepository:
    def __init__(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name) / "repository"
        self.root.mkdir()
        self.environment = os.environ.copy()
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Codelaxy Test")
        self.git("config", "user.email", "codelaxy-test@example.invalid")
        self.git("config", "commit.gpgsign", "false")

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

    def commit_all(self, message: str = "test fixture") -> None:
        self.git("add", "--all")
        self.git("commit", "-m", message)

    def state(self) -> tuple[bytes, ...]:
        commands = (
            ("rev-parse", "--verify", "HEAD"),
            ("symbolic-ref", "-q", "HEAD"),
            (
                "for-each-ref",
                "--format=%(refname) %(objectname)",
                "refs/heads",
                "refs/remotes",
                "refs/stash",
            ),
            ("status", "--porcelain=v2", "-z", "--untracked-files=all"),
            ("ls-files", "--stage", "-z"),
            ("diff", "--cached", "--binary"),
            ("diff", "--binary"),
        )
        return tuple(self.git(*command).stdout for command in commands)


class GitSnapshotTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repository = GitRepository()
        self.addCleanup(self.repository.close)

    def test_unborn_repository_has_no_head_oid(self) -> None:
        self.repository.write("untracked.txt", "untracked\n")

        snapshot = observe_snapshot(self.repository.root, "worktree")

        self.assertIsNone(snapshot.head_oid)
        self.assertEqual(snapshot.changed_files, ("untracked.txt",))

    def test_clean_snapshot_is_deterministic_and_read_only(self) -> None:
        self.repository.write("tracked.txt", "committed\n")
        self.repository.commit_all()

        state_before = self.repository.state()
        first = observe_snapshot(self.repository.root, "worktree")
        second = observe_snapshot(self.repository.root, "worktree")

        self.assertEqual(first, second)
        self.assertEqual(first.changes, ())
        self.assertTrue(first.snapshot_id.startswith("sha256:"))
        self.assertEqual(self.repository.state(), state_before)

    def test_staged_snapshot_ignores_unstaged_and_untracked_content(self) -> None:
        self.repository.write("tracked.txt", "committed\n")
        self.repository.commit_all()

        self.repository.write("tracked.txt", "staged\n")
        self.repository.git("add", "tracked.txt")
        staged_before = observe_snapshot(self.repository.root, "staged")
        worktree_before = observe_snapshot(self.repository.root, "worktree")

        self.repository.write("tracked.txt", "unstaged after staging\n")
        self.repository.write("untracked.txt", "untracked\n")
        staged_after = observe_snapshot(self.repository.root, "staged")
        worktree_after = observe_snapshot(self.repository.root, "worktree")

        self.assertEqual(staged_after, staged_before)
        self.assertNotEqual(
            worktree_after.snapshot_id,
            worktree_before.snapshot_id,
        )
        self.assertEqual(staged_after.changed_files, ("tracked.txt",))
        self.assertIsNone(staged_after.worktree_fingerprint)

    def test_snapshot_represents_rename_deletion_and_worktree_states(self) -> None:
        self.repository.write("original.txt", "rename\n")
        self.repository.write("deleted.txt", "delete\n")
        self.repository.write("modified.txt", "committed\n")
        self.repository.commit_all()

        self.repository.git("mv", "original.txt", "renamed.txt")
        self.repository.git("rm", "deleted.txt")
        self.repository.write("modified.txt", "modified\n")
        self.repository.write("untracked.txt", "untracked\n")

        snapshot = observe_snapshot(self.repository.root, "worktree")
        changes = {change.path: change for change in snapshot.changes}

        self.assertEqual(changes["renamed.txt"].kind, "rename")
        self.assertEqual(
            changes["renamed.txt"].original_path,
            "original.txt",
        )
        self.assertEqual(changes["renamed.txt"].index_status, "R")
        self.assertEqual(changes["deleted.txt"].index_status, "D")
        self.assertEqual(changes["modified.txt"].worktree_status, "M")
        self.assertEqual(changes["untracked.txt"].kind, "untracked")

    def test_snapshot_represents_unmerged_path_without_resolving_it(self) -> None:
        self.repository.write("conflicted.txt", "base\n")
        self.repository.commit_all()

        self.repository.git("switch", "-c", "other")
        self.repository.write("conflicted.txt", "other\n")
        self.repository.commit_all("other change")
        self.repository.git("switch", "main")
        self.repository.write("conflicted.txt", "main\n")
        self.repository.commit_all("main change")
        merge = self.repository.git("merge", "other", check=False)
        self.assertNotEqual(merge.returncode, 0)

        state_before = self.repository.state()
        snapshot = observe_snapshot(self.repository.root, "worktree")

        self.assertEqual(len(snapshot.changes), 1)
        self.assertEqual(snapshot.changes[0].path, "conflicted.txt")
        self.assertEqual(snapshot.changes[0].kind, "unmerged")
        self.assertEqual(self.repository.state(), state_before)

    def test_worktree_content_changes_fingerprint_when_status_is_unchanged(
        self,
    ) -> None:
        self.repository.write("tracked.txt", "committed\n")
        self.repository.commit_all()

        self.repository.write("tracked.txt", "first modification\n")
        first = observe_snapshot(self.repository.root, "worktree")

        self.repository.write("tracked.txt", "second modification\n")
        second = observe_snapshot(self.repository.root, "worktree")

        self.assertEqual(first.changes, second.changes)
        self.assertNotEqual(
            first.worktree_fingerprint,
            second.worktree_fingerprint,
        )
        self.assertNotEqual(first.snapshot_id, second.snapshot_id)

    def test_invalid_scope_and_non_repository_are_rejected(self) -> None:
        with self.assertRaisesRegex(
            GitSnapshotError,
            "invalid snapshot scope",
        ):
            observe_snapshot(self.repository.root, "galaxy")

        with tempfile.TemporaryDirectory() as temporary_directory:
            with self.assertRaisesRegex(GitSnapshotError, "rev-parse"):
                observe_snapshot(temporary_directory, "worktree")

    @unittest.skipUnless(shutil.which("bash"), "bash is required")
    def test_statusman_json_matches_engine_and_preserves_repository(
        self,
    ) -> None:
        shutil.copytree(ROOT / "tools", self.repository.root / "tools")
        self.repository.write("tracked.txt", "committed\n")
        self.repository.commit_all()

        self.repository.write("tracked.txt", "staged\n")
        self.repository.git("add", "tracked.txt")
        self.repository.write("tracked.txt", "unstaged\n")
        self.repository.write("untracked.txt", "untracked\n")

        state_before = self.repository.state()

        bash = shutil.which("bash")
        if bash is None:
            self.skipTest("bash is required")

        result = subprocess.run(
            [
                bash,
                (
                    self.repository.root
                    / "tools"
                    / "bin"
                    / "statusman"
                ).as_posix(),
                "--json",
                "--staged",
            ],
            cwd=self.repository.root,
            env=self.repository.environment,
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(
            result.returncode,
            0,
            result.stdout + result.stderr,
        )
        self.assertEqual(result.stderr, "")
        self.assertEqual(
            decode_record(result.stdout),
            observe_snapshot(self.repository.root, "staged"),
        )
        self.assertEqual(self.repository.state(), state_before)


if __name__ == "__main__":
    unittest.main()
