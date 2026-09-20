"""Environment boundary for subprocesses using disposable Git repositories."""

from __future__ import annotations

import os
import subprocess


def git_local_environment_variables() -> tuple[str, ...]:
    # Discovery itself must work even with invalid hook paths/configuration.
    discovery_environment = {
        key: value for key, value in os.environ.items()
        if not key.upper().startswith("GIT_")
    }
    result = subprocess.run(
        ["git", "rev-parse", "--local-env-vars"],
        env=discovery_environment,
        check=True,
        capture_output=True,
        text=True,
    )
    return tuple(filter(None, result.stdout.splitlines()))


def isolated_git_environment() -> dict[str, str]:
    """Preserve runtime settings, but never inherit another repository."""
    local_variables = set(git_local_environment_variables())
    return {
        key: value for key, value in os.environ.items()
        if key.upper() not in local_variables
        and not key.upper().startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_"))
    }
