from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tests.git_test_support import isolated_git_environment

BASH_SCRIPTS = (
    ROOT / "tools" / "statusman.sh",
    ROOT / "tools" / "doorman.sh",
    ROOT / "tools" / "format.sh",
    ROOT / "tools" / "format-check.sh",
)

RUNTIME_USERS = BASH_SCRIPTS + (
    ROOT / "tools" / "mrproper.sh",
    ROOT / "tools" / "verify.sh",
    ROOT / "tools" / "ironman.sh",
)

NATIVE_TOOL_USERS = {
    ROOT / "tools" / "format-check.sh": "clang-format",
    ROOT / "tools" / "format.sh": "clang-format",
    ROOT / "tools" / "ironman.sh": "g++ --version",
    ROOT / "tools" / "mrproper.sh": '"$PYTHON"',
    ROOT / "tools" / "statusman.sh": '"$PYTHON"',
    ROOT / "tools" / "verify.sh": "g++ -std=c++20",
}

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
                self.assertIn("git rev-parse --show-toplevel", content)
                self.assertIn('cygpath -u "$ROOT_DIR"', content)
                self.assertIn('TARGET="$ROOT_DIR/tools/$TOOL.sh"', content)
                self.assertNotIn("Projects/CPP", content)

    def test_runtime_users_do_not_use_ambient_mktemp(self) -> None:
        for script in RUNTIME_USERS:
            with self.subTest(script=script.name):
                content = script.read_text(encoding="utf-8")
                self.assertIn('tools/lib/runtime.sh', content)
                self.assertNotRegex(content, r"(?m)=\$\(mktemp(?:\s|\))")

    def test_native_tools_cross_the_runtime_boundary(self) -> None:
        for script, command in NATIVE_TOOL_USERS.items():
            with self.subTest(script=script.name, command=command):
                content = script.read_text(encoding="utf-8")
                self.assertIn("codelaxy_native_exec", content)
                self.assertIn(command, content)

    def test_runtime_owns_temp_and_snapshot_space(self) -> None:
        bash = shutil.which("bash")

        if bash is None:
            self.skipTest("bash is required")

        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory) / "repository"
            shutil.copytree(ROOT / "tools", repository / "tools")
            self.run_git(repository, "init", "-b", "main")

            program = (
                ". tools/lib/runtime.sh && "
                "codelaxy_runtime_init && "
                "TEMP_FILE=$(codelaxy_temp_file test) && "
                "SNAPSHOT_DIR=$(codelaxy_snapshot_dir staged) && "
                "NATIVE_VALUES=$(codelaxy_native_exec sh -c "
                "'printf \"%s|%s|%s\" "
                '"$TMPDIR" "$TEMP" "$TMP"'"') && "
                'test "$TMPDIR" = "$CODELAXY_TEMP_DIR" && '
                'test "$TEMP" = "$CODELAXY_NATIVE_TEMP" && '
                'test "$TMP" = "$CODELAXY_NATIVE_TEMP" && '
                'test -z "${CODELAXY_RUNTIME_ROOT+x}" && '
                'test "$NATIVE_VALUES" = '
                '"$CODELAXY_NATIVE_TEMP|$CODELAXY_NATIVE_TEMP|'
                '$CODELAXY_NATIVE_TEMP" && '
                "printf '%s\\n%s\\n%s\\n%s\\n%s\\n' "
                '"$CODELAXY_RUNTIME_BASE" "$TEMP_FILE" '
                '"$SNAPSHOT_DIR" "$TMPDIR" "$CODELAXY_NATIVE_TEMP"'
            )

            result = subprocess.run(
                [
                    bash,
                    "-c",
                    program,
                ],
                cwd=repository,
                env=isolated_git_environment(),
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(
                result.returncode,
                0,
                result.stdout + result.stderr,
            )
            lines = result.stdout.splitlines()
            self.assertEqual(len(lines), 5)

            runtime_root = lines[0]
            self.assertTrue(runtime_root.endswith("/.git/codelaxy/runtime"))
            self.assertTrue(lines[1].startswith(runtime_root + "/sessions/"))
            self.assertTrue(lines[2].startswith(runtime_root + "/sessions/"))
            self.assertTrue(lines[3].startswith(runtime_root + "/sessions/"))

    def test_snapshot_runtime_root_crosses_only_explicit_boundaries(self) -> None:
        runtime = (ROOT / "tools" / "lib" / "runtime.sh").read_text(
            encoding="utf-8"
        )
        doorman = (ROOT / "tools" / "doorman.sh").read_text(encoding="utf-8")
        ironman = (ROOT / "tools" / "ironman.sh").read_text(encoding="utf-8")

        self.assertNotIn("export CODELAXY_RUNTIME_ROOT", runtime)
        self.assertIn("unset CODELAXY_RUNTIME_ROOT", runtime)
        self.assertEqual(
            doorman.count('CODELAXY_RUNTIME_ROOT="$CODELAXY_RUNTIME_BASE"'),
            2,
        )
        self.assertEqual(
            ironman.count('CODELAXY_RUNTIME_ROOT="$CODELAXY_RUNTIME_BASE"'),
            1,
        )

    def test_runtime_cleanup_refuses_an_unowned_directory(self) -> None:
        bash = shutil.which("bash")

        if bash is None:
            self.skipTest("bash is required")

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_root = Path(temporary_directory)
            unowned = temporary_root / "must-survive"
            unowned.mkdir()
            runtime_script = temporary_root / "tools" / "lib" / "runtime.sh"
            runtime_script.parent.mkdir(parents=True)
            shutil.copy2(ROOT / "tools" / "lib" / "runtime.sh", runtime_script)

            result = subprocess.run(
                [
                    bash,
                    "-c",
                    ". tools/lib/runtime.sh && "
                    'CODELAXY_RUNTIME_BASE="$PWD/runtime" && '
                    'CODELAXY_RUNTIME_SESSION="$PWD/must-survive" && '
                    "codelaxy_runtime_cleanup && "
                    'test -d "$PWD/must-survive"',
                ],
                cwd=temporary_root,
                env=isolated_git_environment(),
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(
                result.returncode,
                0,
                result.stdout + result.stderr,
            )

    def test_installed_launcher_selects_current_worktree(self) -> None:
        bash = shutil.which("bash")

        if bash is None:
            self.skipTest("bash is required")

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_root = Path(temporary_directory)
            install_dir = temporary_root / "bin"
            primary = temporary_root / "primary"
            linked = temporary_root / "linked"

            primary_tool = primary / "tools" / "statusman.sh"
            primary_tool.parent.mkdir(parents=True)
            primary_tool.write_text(
                "#!/usr/bin/env bash\nprintf '%s\\n' primary\n",
                encoding="utf-8",
            )
            self.run_git(primary, "init", "-b", "main")
            self.run_git(primary, "config", "user.name", "Codelaxy Test")
            self.run_git(
                primary,
                "config",
                "user.email",
                "codelaxy-test@example.invalid",
            )
            self.run_git(primary, "config", "commit.gpgsign", "false")
            self.run_git(primary, "add", "tools/statusman.sh")
            self.run_git(primary, "commit", "-m", "test fixture")
            self.run_git(primary, "worktree", "add", "-b", "linked", str(linked))

            linked_tool = linked / "tools" / "statusman.sh"
            linked_tool.write_text(
                "#!/usr/bin/env bash\nprintf '%s\\n' linked\n",
                encoding="utf-8",
            )

            install = subprocess.run(
                [
                    bash,
                    (ROOT / "tools" / "install-launchers.sh").as_posix(),
                    install_dir.as_posix(),
                ],
                env=isolated_git_environment(),
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                install.returncode,
                0,
                install.stdout + install.stderr,
            )

            for repository, marker in ((primary, "primary"), (linked, "linked")):
                result = subprocess.run(
                    [bash, (install_dir / "statusman").as_posix()],
                    cwd=repository,
                    env=isolated_git_environment(),
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(
                    result.returncode,
                    0,
                    result.stdout + result.stderr,
                )
                self.assertEqual(result.stdout, marker + "\n")

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

            environment = isolated_git_environment()
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

    def test_mrproper_shell_delegates_cleanup_to_single_engine(self) -> None:
        script = (ROOT / "tools" / "mrproper.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn(
            '"$PYTHON" "$ROOT_DIR/tools/mrproper.py"',
            script,
        )
        self.assertNotIn(
            "tools/format.sh",
            script,
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
            env=isolated_git_environment(),
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
            env=isolated_git_environment(),
            check=True,
            capture_output=True,
            text=True,
        )

    def test_legacy_launchers_match_canonical_launcher(self) -> None:
        canonical = (
            ROOT / "tools" / "bin" / "statusman"
        ).read_bytes()

        for launcher in LAUNCHERS:
            with self.subTest(launcher=launcher.name):
                self.assertEqual(
                    launcher.read_bytes(),
                    canonical,
                )


if __name__ == "__main__":
    unittest.main()
