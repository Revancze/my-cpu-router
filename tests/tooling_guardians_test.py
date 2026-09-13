from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1]


class RepositoryFixture:
    def __init__(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name) / "repository"
        self.fake_bin = Path(self.temporary_directory.name) / "fake-bin"
        self.fake_bin.mkdir()

        shutil.copytree(SOURCE_ROOT / "tools", self.root / "tools")
        shutil.copy2(SOURCE_ROOT / ".clang-format", self.root / ".clang-format")
        shutil.copy2(SOURCE_ROOT / ".gitignore", self.root / ".gitignore")

        self.write(
            self.fake_bin / "clang-format",
            """#!/usr/bin/env bash
set -u

IN_PLACE=0
FILE=""

for ARG
do
    case "$ARG" in
        -i) IN_PLACE=1 ;;
        --style=*) ;;
        *) FILE=$ARG ;;
    esac
done

if [ "$IN_PLACE" -eq 0 ]
then
    cat -- "$FILE"
fi
""",
        )
        clang_format = self.fake_bin / "clang-format"
        clang_format.chmod(clang_format.stat().st_mode | stat.S_IXUSR)

        self.environment = os.environ.copy()
        for variable in (
            "FORMAT_CHECK_QUIET",
            "FORMAT_ROOT",
            "IRONMAN_EMBEDDED",
            "IRONMAN_ROOT",
            "IRONMAN_SNAPSHOT_MODE",
            "VERIFY_EMBEDDED",
        ):
            self.environment.pop(variable, None)
        self.environment["PATH"] = (
            str(self.fake_bin)
            + os.pathsep
            + self.environment.get("PATH", "")
        )

        self.git("init", "-b", "main")
        self.git("config", "user.name", "Codelaxy Test")
        self.git("config", "user.email", "codelaxy-test@example.invalid")
        self.git("config", "commit.gpgsign", "false")

    def close(self) -> None:
        self.temporary_directory.cleanup()

    def write(self, path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content.encode("utf-8"))

    def git(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *arguments],
            cwd=self.root,
            env=self.environment,
            check=True,
            capture_output=True,
            text=True,
        )

    def commit_all(self) -> None:
        self.git("add", ".clang-format", ".gitignore", "tools")
        for path in sorted(self.root.iterdir()):
            if path.name in {".git", ".clang-format", ".gitignore", "tools"}:
                continue
            self.git("add", path.name)
        self.git("commit", "-m", "test fixture")

    def run_tool(self, name: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.root / "tools" / "bin" / name)],
            cwd=self.root,
            env=self.environment,
            check=False,
            capture_output=True,
            text=True,
        )

    def git_state(self) -> tuple[str, ...]:
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
            ("status", "--porcelain=v2", "--branch", "--untracked-files=all"),
            ("ls-files", "--stage"),
            ("diff", "--cached", "--binary"),
            ("diff", "--binary"),
        )
        return tuple(self.git(*command).stdout for command in commands)


class GuardianAuthorityTest(unittest.TestCase):
    def setUp(self) -> None:
        if shutil.which("bash") is None:
            self.skipTest("bash is required")

        self.fixture = RepositoryFixture()
        self.addCleanup(self.fixture.close)

    def test_statusman_preserves_clean_repository_state(self) -> None:
        self.fixture.write(self.fixture.root / "tracked.txt", "committed\n")
        self.fixture.commit_all()

        state_before = self.fixture.git_state()
        result = self.fixture.run_tool("statusman")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Working tree clean.", result.stdout)
        self.assertEqual(self.fixture.git_state(), state_before)

    def test_statusman_preserves_mixed_repository_state(self) -> None:
        tracked = self.fixture.root / "tracked.txt"
        self.fixture.write(tracked, "committed\n")
        self.fixture.commit_all()

        self.fixture.write(tracked, "staged\n")
        self.fixture.git("add", "tracked.txt")
        self.fixture.write(tracked, "unstaged\n")
        self.fixture.write(self.fixture.root / "untracked.txt", "untracked\n")

        state_before = self.fixture.git_state()
        result = self.fixture.run_tool("statusman")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("STATUSMAN", result.stdout)
        self.assertEqual(self.fixture.git_state(), state_before)

    def test_statusman_reports_staged_rename_and_deletion_without_changes(self) -> None:
        original = self.fixture.root / "original.txt"
        deleted = self.fixture.root / "deleted.txt"
        self.fixture.write(original, "rename me\n")
        self.fixture.write(deleted, "delete me\n")
        self.fixture.commit_all()

        self.fixture.git("mv", "original.txt", "renamed.txt")
        self.fixture.git("rm", "deleted.txt")

        state_before = self.fixture.git_state()
        result = self.fixture.run_tool("statusman")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("original.txt", result.stdout)
        self.assertIn("renamed.txt", result.stdout)
        self.assertIn("deleted.txt", result.stdout)
        self.assertEqual(self.fixture.git_state(), state_before)

    def test_statusman_reports_conflict_without_resolving_it(self) -> None:
        conflicted = self.fixture.root / "conflicted.txt"
        self.fixture.write(conflicted, "base\n")
        self.fixture.commit_all()

        self.fixture.git("switch", "-c", "other")
        self.fixture.write(conflicted, "other\n")
        self.fixture.git("add", "conflicted.txt")
        self.fixture.git("commit", "-m", "other change")

        self.fixture.git("switch", "main")
        self.fixture.write(conflicted, "main\n")
        self.fixture.git("add", "conflicted.txt")
        self.fixture.git("commit", "-m", "main change")

        merge = subprocess.run(
            ["git", "merge", "other"],
            cwd=self.fixture.root,
            env=self.fixture.environment,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(merge.returncode, 0)

        state_before = self.fixture.git_state()
        result = self.fixture.run_tool("statusman")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"✖\s+conflicted\.txt")
        self.assertIn("Repository needs attention", result.stdout)
        self.assertEqual(self.fixture.git_state(), state_before)

    def test_mrproper_changes_worktree_but_preserves_index(self) -> None:
        tracked = self.fixture.root / "tracked.txt"
        self.fixture.write(tracked, "committed\n")
        self.fixture.commit_all()

        self.fixture.write(tracked, "staged value  \n")
        self.fixture.git("add", "tracked.txt")
        staged_before = self.fixture.git("show", ":tracked.txt").stdout
        self.fixture.write(tracked, "staged value  \n\n\n")

        result = self.fixture.run_tool("mrproper")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("WORKTREE CLEANED", result.stdout)
        self.assertEqual(tracked.read_bytes(), b"staged value\n")
        self.assertEqual(
            self.fixture.git("show", ":tracked.txt").stdout,
            staged_before,
        )

    @unittest.skipUnless(shutil.which("g++"), "g++ is required")
    def test_ironman_runs_tests_without_changing_repository(self) -> None:
        self.fixture.write(
            self.fixture.root / "tests" / "sample_test.cpp",
            "int main() { return 0; }\n",
        )
        self.fixture.commit_all()

        state_before = self.fixture.git_state()
        result = self.fixture.run_tool("ironman")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1 / 1 tests passed", result.stdout)
        self.assertIn("Source integrity preserved", result.stdout)
        self.assertEqual(self.fixture.git_state(), state_before)

    @unittest.skipUnless(shutil.which("g++"), "g++ is required")
    def test_ironman_rejects_verification_that_changes_worktree(self) -> None:
        tracked = self.fixture.root / "tracked.txt"
        self.fixture.write(tracked, "committed\n")
        self.fixture.commit_all()
        self.fixture.write(
            self.fixture.root / "tools" / "verify.sh",
            "#!/usr/bin/env bash\nprintf 'changed\\n' > tracked.txt\n",
        )

        result = self.fixture.run_tool("ironman")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("INTEGRITY VIOLATION", result.stdout)

    @unittest.skipUnless(shutil.which("g++"), "g++ is required")
    def test_ironman_reports_failing_test_without_changing_repository(self) -> None:
        self.fixture.write(
            self.fixture.root / "tests" / "failing_test.cpp",
            "int main() { return 7; }\n",
        )
        self.fixture.commit_all()

        state_before = self.fixture.git_state()
        result = self.fixture.run_tool("ironman")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("failing_test · test failed", result.stdout)
        self.assertIn("VERIFICATION FAILED", result.stdout)
        self.assertEqual(self.fixture.git_state(), state_before)

    @unittest.skipUnless(shutil.which("g++"), "g++ is required")
    def test_doorman_verifies_staged_snapshot_not_unstaged_content(self) -> None:
        test_file = self.fixture.root / "tests" / "sample_test.cpp"
        self.fixture.write(test_file, "int main() { return 0; }\n")
        self.fixture.commit_all()

        staged_content = "int main() { return 0; } // staged\n"
        unstaged_content = "int main() { return 1; } // unstaged\n"
        self.fixture.write(test_file, staged_content)
        self.fixture.git("add", "tests/sample_test.cpp")
        self.fixture.write(test_file, unstaged_content)
        state_before = self.fixture.git_state()

        result = self.fixture.run_tool("doorman")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("ACCESS GRANTED", result.stdout)
        self.assertIn("Staged snapshot verified", result.stdout)
        self.assertEqual(test_file.read_text(encoding="utf-8"), unstaged_content)
        self.assertEqual(
            self.fixture.git("show", ":tests/sample_test.cpp").stdout,
            staged_content,
        )
        self.assertEqual(self.fixture.git_state(), state_before)


if __name__ == "__main__":
    unittest.main()
