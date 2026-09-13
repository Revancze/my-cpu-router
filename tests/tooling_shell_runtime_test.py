from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

BASH_SCRIPTS = (
    ROOT / "tools" / "statusman.sh",
    ROOT / "tools" / "doorman.sh",
    ROOT / "tools" / "format.sh",
    ROOT / "tools" / "format-check.sh",
)

LAUNCHERS = (
    ROOT / "tools" / "bin" / "statusman",
    ROOT / "tools" / "bin" / "mrproper",
    ROOT / "tools" / "bin" / "ironman",
    ROOT / "tools" / "bin" / "doorman",
)


class ToolingShellRuntimeTest(unittest.TestCase):
    def test_scripts_with_nul_delimited_reads_require_bash(self) -> None:
        for script in BASH_SCRIPTS:
            with self.subTest(script=script.name):
                first_line = script.read_text(encoding="utf-8").splitlines()[0]
                self.assertEqual(first_line, "#!/usr/bin/env bash")

    def test_public_launchers_delegate_to_bash(self) -> None:
        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher.name):
                content = launcher.read_text(encoding="utf-8")
                self.assertTrue(content.endswith("\n"))
                self.assertIn('exec bash "$TARGET" "$@"', content)
                self.assertNotIn('exec sh "$TARGET" "$@"', content)

    def test_statusman_launcher_ignores_an_incompatible_sh(self) -> None:
        bash = shutil.which("bash")

        if bash is None:
            self.skipTest("bash is required")

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_root = Path(temporary_directory)
            repository = temporary_root / "repository"
            fake_bin = temporary_root / "fake-bin"
            fake_bin.mkdir()

            shutil.copytree(ROOT / "tools", repository / "tools")

            self.run_git(repository, "init", "-b", "main")
            self.run_git(repository, "config", "user.name", "Codelaxy Test")
            self.run_git(
                repository,
                "config",
                "user.email",
                "codelaxy-test@example.invalid",
            )
            self.run_git(repository, "config", "commit.gpgsign", "false")
            self.run_git(repository, "add", "tools")
            self.run_git(repository, "commit", "-m", "test fixture")

            incompatible_sh = fake_bin / "sh"
            incompatible_sh.write_text(
                "#!/usr/bin/env bash\nexit 97\n",
                encoding="utf-8",
            )
            incompatible_sh.chmod(
                incompatible_sh.stat().st_mode | stat.S_IXUSR
            )

            environment = os.environ.copy()
            environment["PATH"] = (
                str(fake_bin) + os.pathsep + environment.get("PATH", "")
            )

            status_before = self.git_status(repository)

            result = subprocess.run(
                [
                    bash,
                    (repository / "tools" / "bin" / "statusman").as_posix(),
                ],
                cwd=repository,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(
                result.returncode,
                0,
                result.stdout + result.stderr,
            )
            self.assertIn("STATUSMAN", result.stdout)
            self.assertEqual(
                self.git_status(repository),
                status_before,
            )

    def git_status(self, repository: Path) -> str:
        result = subprocess.run(
            [
                "git",
                "status",
                "--porcelain=v1",
                "--untracked-files=all",
            ],
            cwd=repository,
            check=True,
            capture_output=True,
            text=True,
        )

        return result.stdout

    def run_git(self, repository: Path, *arguments: str) -> None:
        repository.mkdir(parents=True, exist_ok=True)

        subprocess.run(
            ["git", *arguments],
            cwd=repository,
            check=True,
            capture_output=True,
            text=True,
        )


if __name__ == "__main__":
    unittest.main()
