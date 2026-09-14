"""Machine-readable command line interface for read-only Git snapshots."""

from __future__ import annotations

import argparse
import sys

from .git_snapshot import GitSnapshotError, observe_snapshot
from .protocol import encode_record


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Emit a Codelaxy Git snapshot")
    parser.add_argument("--repository", default=".")
    parser.add_argument("--scope", choices=("staged", "worktree"), default="worktree")
    options = parser.parse_args(arguments)

    try:
        snapshot = observe_snapshot(options.repository, options.scope)
    except GitSnapshotError as error:
        print(f"STATUSMAN ERROR: {error}", file=sys.stderr)
        return 1

    sys.stdout.write(encode_record(snapshot))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
