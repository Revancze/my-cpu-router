"""Machine-readable command line interface for read-only Git snapshots."""

from __future__ import annotations

import argparse
import sys

from .contracts import Snapshot
from .git_snapshot import GitSnapshotError, observe_snapshot
from .protocol import encode_record


def _write_stdout(payload: str) -> None:
    """Write deterministic UTF-8 bytes with unchanged LF line endings."""

    encoded = payload.encode("utf-8")

    if hasattr(sys.stdout, "buffer"):
        sys.stdout.buffer.write(encoded)
    else:
        # Useful for tests that replace stdout with an in-memory text stream.
        sys.stdout.write(payload)


def _emit_statusman_facts(snapshot: Snapshot) -> None:
    staged = 0
    unstaged = 0
    untracked = 0
    conflicts = 0

    for change in snapshot.changes:
        if change.kind == "untracked":
            untracked += 1
            continue

        if change.kind == "unmerged":
            conflicts += 1
            continue

        if change.index_status != ".":
            staged += 1

        if change.worktree_status != ".":
            unstaged += 1

    head_oid = snapshot.head_oid or ""

    payload = (
        f"HEAD_OID\t{head_oid}\n"
        f"STAGED\t{staged}\n"
        f"UNSTAGED\t{unstaged}\n"
        f"UNTRACKED\t{untracked}\n"
        f"CONFLICTS\t{conflicts}\n"
    )

    _write_stdout(payload)


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Emit a Codelaxy Git snapshot"
    )
    parser.add_argument(
        "--repository",
        default=".",
    )
    parser.add_argument(
        "--scope",
        choices=("staged", "worktree"),
        default="worktree",
    )
    parser.add_argument(
        "--statusman-facts",
        action="store_true",
        help="emit compact human-renderer facts instead of JSON",
    )

    options = parser.parse_args(arguments)

    try:
        snapshot = observe_snapshot(
            options.repository,
            options.scope,
        )
    except GitSnapshotError as error:
        print(
            f"STATUSMAN ERROR: {error}",
            file=sys.stderr,
        )
        return 1

    if options.statusman_facts:
        if options.scope != "worktree":
            print(
                "STATUSMAN ERROR: "
                "--statusman-facts requires worktree scope.",
                file=sys.stderr,
            )
            return 1

        _emit_statusman_facts(snapshot)
        return 0

    _write_stdout(encode_record(snapshot))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
