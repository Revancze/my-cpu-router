from __future__ import annotations

import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tests.git_test_support import (
    git_local_environment_variables,
    isolated_git_environment,
)
from tests.tooling_snapshot_test import GitRepository


class GitEnvironmentTest(unittest.TestCase):
    def test_invalid_parent_environment_is_removed_without_mutating_it(self):
        poison = {
            "GIT_DIR": "/does-not-exist/repository",
            "GIT_WORK_TREE": "/does-not-exist/worktree",
            "GIT_INDEX_FILE": "/does-not-exist/index",
            "GIT_CONFIG_COUNT": "invalid",
            "GIT_CONFIG_KEY_0": "core.bare",
            "GIT_CONFIG_VALUE_0": "true",
            "NO_COLOR": "1",
        }
        with patch.dict(os.environ, poison):
            before = dict(os.environ)
            environment = isolated_git_environment()
            self.assertEqual(dict(os.environ), before)
            for key in git_local_environment_variables():
                self.assertNotIn(key, environment)
            self.assertNotIn("GIT_CONFIG_KEY_0", environment)
            self.assertNotIn("GIT_CONFIG_VALUE_0", environment)
            self.assertEqual(environment["PATH"], before["PATH"])
            self.assertEqual(environment["NO_COLOR"], "1")

    def test_tooling_suite_preserves_foreign_repository_under_hook_environment(self):
        parent = GitRepository()
        self.addCleanup(parent.close)
        parent.write("sentinel.txt", "committed\n")
        parent.commit_all()
        parent.write("sentinel.txt", "staged\n")
        parent.git("add", "sentinel.txt")
        parent.write("sentinel.txt", "unstaged\n")
        metadata = parent.root / ".git"

        def state():
            return (
                parent.state(),
                (metadata / "config").read_bytes(),
                (metadata / "index").read_bytes(),
                (metadata / "HEAD").read_bytes(),
            )

        before = state()
        environment = isolated_git_environment()
        environment.update({
            "GIT_DIR": metadata.as_posix(),
            "GIT_COMMON_DIR": metadata.as_posix(),
            "GIT_WORK_TREE": parent.root.as_posix(),
            "GIT_INDEX_FILE": (metadata / "index").as_posix(),
            "GIT_OBJECT_DIRECTORY": (metadata / "objects").as_posix(),
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "core.bare",
            "GIT_CONFIG_VALUE_0": "true",
            "PYTHONDONTWRITEBYTECODE": "1",
        })
        # Automatically cover future tooling modules; exclude this driver to
        # avoid recursion. Poison points only at a disposable sentinel repo.
        modules = [
            f"tests.{path.stem}"
            for path in sorted((ROOT / "tests").glob("tooling*_test.py"))
            if path.resolve() != Path(__file__).resolve()
        ]
        result = subprocess.run(
            [sys.executable, "-m", "unittest", *modules],
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
            timeout=300,
        )
        self.assertEqual(state(), before, "Tooling tests mutated the parent repository")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
