"""Read-only Git observation and deterministic repository fingerprints."""

from __future__ import annotations

import hashlib
import json
import os
import stat
import subprocess
from pathlib import Path

from .contracts import SCHEMA_VERSION, VALID_SCOPES, Change, Snapshot


class GitSnapshotError(RuntimeError):
    """Raised when an exact snapshot cannot be obtained safely."""


def _run_git(root: Path, *arguments: str, allow_failure: bool = False) -> bytes:
    environment = os.environ.copy()
    environment["GIT_OPTIONAL_LOCKS"] = "0"
    result = subprocess.run(
        ["git", *arguments],
        cwd=root,
        env=environment,
        check=False,
        capture_output=True,
    )
    if result.returncode != 0 and not allow_failure:
        message = result.stderr.decode("utf-8", errors="replace").strip()
        raise GitSnapshotError(
            f"git {' '.join(arguments)} failed: {message or result.returncode}"
        )
    return result.stdout if result.returncode == 0 else b""


def _decode_path(value: bytes) -> str:
    return os.fsdecode(value)


def _parse_status(status: bytes) -> tuple[Change, ...]:
    records = status.split(b"\0")
    changes: list[Change] = []
    index = 0

    while index < len(records):
        record = records[index]
        index += 1
        if not record:
            continue

        record_type = record[:1]
        original_path: str | None = None

        if record_type == b"1":
            fields = record.split(b" ", 8)
            if len(fields) != 9:
                raise GitSnapshotError("invalid ordinary porcelain-v2 record")
            xy = fields[1]
            kind = "ordinary"
            path = _decode_path(fields[8])
        elif record_type == b"2":
            fields = record.split(b" ", 9)
            if len(fields) != 10 or index >= len(records):
                raise GitSnapshotError("invalid rename porcelain-v2 record")
            xy = fields[1]
            operation = fields[8][:1]
            if operation == b"R":
                kind = "rename"
            elif operation == b"C":
                kind = "copy"
            else:
                raise GitSnapshotError("unknown rename/copy porcelain-v2 operation")
            path = _decode_path(fields[9])
            original_path = _decode_path(records[index])
            index += 1
        elif record_type == b"u":
            fields = record.split(b" ", 10)
            if len(fields) != 11:
                raise GitSnapshotError("invalid unmerged porcelain-v2 record")
            xy = fields[1]
            kind = "unmerged"
            path = _decode_path(fields[10])
        elif record_type == b"?":
            xy = b"??"
            kind = "untracked"
            path = _decode_path(record[2:])
        else:
            raise GitSnapshotError(
                f"unsupported porcelain-v2 record type: {record_type!r}"
            )

        if len(xy) != 2:
            raise GitSnapshotError("invalid porcelain-v2 XY status")

        changes.append(
            Change(
                path=path,
                kind=kind,
                index_status=chr(xy[0]),
                worktree_status=chr(xy[1]),
                original_path=original_path,
            )
        )

    return tuple(sorted(changes, key=lambda change: os.fsencode(change.path)))


def _fingerprint(payload: bytes) -> str:
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def _feed(hasher: object, payload: bytes) -> None:
    hasher.update(len(payload).to_bytes(8, byteorder="big"))  # type: ignore[attr-defined]
    hasher.update(payload)  # type: ignore[attr-defined]


def _worktree_fingerprint(root: Path, status: bytes) -> str:
    hasher = hashlib.sha256()
    _feed(hasher, b"codelaxy-worktree-v1")
    _feed(hasher, status)

    listed_paths = _run_git(
        root,
        "ls-files",
        "-z",
        "--cached",
        "--others",
        "--exclude-standard",
    )
    paths = sorted(path for path in listed_paths.split(b"\0") if path)

    for encoded_path in paths:
        path = root / _decode_path(encoded_path)
        _feed(hasher, encoded_path)

        try:
            metadata = path.lstat()
        except FileNotFoundError:
            _feed(hasher, b"missing")
            continue

        if stat.S_ISLNK(metadata.st_mode):
            _feed(hasher, b"symlink")
            _feed(hasher, os.fsencode(os.readlink(path)))
        elif stat.S_ISREG(metadata.st_mode):
            executable = b"executable" if metadata.st_mode & stat.S_IXUSR else b"file"
            _feed(hasher, executable)
            _feed(hasher, path.read_bytes())
        elif stat.S_ISDIR(metadata.st_mode):
            _feed(hasher, b"directory")
        else:
            _feed(hasher, b"special")

    return "sha256:" + hasher.hexdigest()


def _snapshot_id(
    *,
    scope: str,
    head_oid: str | None,
    index_fingerprint: str,
    worktree_fingerprint: str | None,
    changes: tuple[Change, ...],
) -> str:
    identity = {
        "schema_version": SCHEMA_VERSION,
        "scope": scope,
        "head_oid": head_oid,
        "index_fingerprint": index_fingerprint,
        "worktree_fingerprint": worktree_fingerprint,
        "changes": [change.to_dict() for change in changes],
    }
    serialized = json.dumps(
        identity,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8", errors="surrogateescape")
    return _fingerprint(serialized)


def observe_snapshot(repository: str | os.PathLike[str], scope: str) -> Snapshot:
    """Observe one repository without writing files, refs, objects, or the index."""

    if scope not in VALID_SCOPES:
        raise GitSnapshotError(f"invalid snapshot scope: {scope!r}")

    requested_root = Path(repository).resolve()
    root_output = _run_git(requested_root, "rev-parse", "--show-toplevel")
    root = Path(_decode_path(root_output.rstrip(b"\r\n"))).resolve()

    head_output = _run_git(root, "rev-parse", "--verify", "HEAD", allow_failure=True)
    if head_output:
        head_oid = head_output.decode("ascii").strip()
    else:
        unborn_head = _run_git(
            root,
            "symbolic-ref",
            "-q",
            "HEAD",
            allow_failure=True,
        )
        if not unborn_head:
            raise GitSnapshotError("could not resolve HEAD")
        head_oid = None

    index_payload = _run_git(root, "ls-files", "--stage", "-z")
    index_fingerprint = _fingerprint(index_payload)

    status_payload = _run_git(
        root,
        "status",
        "--porcelain=v2",
        "-z",
        "--untracked-files=all",
    )
    all_changes = _parse_status(status_payload)

    if scope == "staged":
        changes = tuple(
            Change(
                path=change.path,
                kind=change.kind,
                index_status=change.index_status,
                worktree_status=".",
                original_path=change.original_path,
            )
            for change in all_changes
            if change.kind != "untracked" and change.index_status != "."
        )
        worktree_fingerprint = None
    else:
        changes = all_changes
        worktree_fingerprint = _worktree_fingerprint(root, status_payload)

    snapshot_id = _snapshot_id(
        scope=scope,
        head_oid=head_oid,
        index_fingerprint=index_fingerprint,
        worktree_fingerprint=worktree_fingerprint,
        changes=changes,
    )
    return Snapshot(
        snapshot_id=snapshot_id,
        scope=scope,
        head_oid=head_oid,
        index_fingerprint=index_fingerprint,
        worktree_fingerprint=worktree_fingerprint,
        changes=changes,
    )
