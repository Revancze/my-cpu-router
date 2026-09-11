from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


TEXT_SUFFIXES = {
    ".c",
    ".cpp",
    ".h",
    ".hpp",
    ".json",
    ".md",
    ".py",
    ".sh",
    ".cmd",
    ".bat",
    ".txt",
    ".yml",
    ".yaml",
    ".toml",
}

TEXT_NAMES = {
    ".editorconfig",
    ".gitattributes",
    ".gitignore",
}


def emit(*fields: object) -> None:
    line = "\t".join(str(field) for field in fields)
    sys.stdout.buffer.write(
        line.encode("utf-8") + b"\n"
    )


def repository_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        capture_output=True,
    )

    return Path(
        os.fsdecode(result.stdout.strip())
    )


def git_paths(
    root: Path,
    command: list[str],
) -> set[Path]:
    result = subprocess.run(
        command,
        check=True,
        cwd=root,
        capture_output=True,
    )

    paths: set[Path] = set()

    for raw_name in result.stdout.split(b"\0"):
        if not raw_name:
            continue

        paths.add(
            root / os.fsdecode(raw_name)
        )

    return paths


def changed_files(root: Path) -> list[Path]:
    tracked = git_paths(
        root,
        [
            "git",
            "diff",
            "--name-only",
            "-z",
            "HEAD",
            "--",
        ],
    )

    untracked = git_paths(
        root,
        [
            "git",
            "ls-files",
            "--others",
            "--exclude-standard",
            "-z",
        ],
    )

    return sorted(
        tracked | untracked
    )


def is_text_target(
    path: Path,
    root: Path,
) -> bool:
    relative = (
        path
        .relative_to(root)
        .as_posix()
    )

    if relative.startswith("githooks/"):
        return True

    if path.name in TEXT_NAMES:
        return True

    return (
        path.suffix.lower()
        in TEXT_SUFFIXES
    )


def preferred_newline(
    data: bytes,
    path: Path,
) -> bytes:
    crlf_count = data.count(b"\r\n")

    lf_count = (
        data.count(b"\n")
        - crlf_count
    )

    cr_count = (
        data.count(b"\r")
        - crlf_count
    )

    if (
        crlf_count > 0
        or lf_count > 0
        or cr_count > 0
    ):
        if (
            crlf_count >= lf_count
            and crlf_count >= cr_count
        ):
            return b"\r\n"

        if lf_count >= cr_count:
            return b"\n"

        return b"\r"

    if path.suffix.lower() in {
        ".cmd",
        ".bat",
    }:
        return b"\r\n"

    return b"\n"


def split_line(
    raw_line: bytes,
) -> tuple[bytes, bytes]:
    if raw_line.endswith(b"\r\n"):
        return raw_line[:-2], b"\r\n"

    if raw_line.endswith(b"\n"):
        return raw_line[:-1], b"\n"

    if raw_line.endswith(b"\r"):
        return raw_line[:-1], b"\r"

    return raw_line, b""


def clean_file(
    path: Path,
) -> tuple[int, int, int]:
    original = path.read_bytes()

    if b"\0" in original:
        return 0, 0, 0

    newline = preferred_newline(
        original,
        path,
    )

    lines: list[
        tuple[bytes, bytes]
    ] = []

    trailing_whitespace = 0

    for raw_line in original.splitlines(
        keepends=True
    ):
        content, ending = split_line(
            raw_line
        )

        cleaned_content = (
            content.rstrip(b" \t")
        )

        if cleaned_content != content:
            trailing_whitespace += 1

        lines.append(
            (
                cleaned_content,
                ending,
            )
        )

    extra_eof_blank_lines = 0

    while (
        lines
        and lines[-1][0] == b""
    ):
        lines.pop()
        extra_eof_blank_lines += 1

    missing_final_newline = 0

    if not lines:
        cleaned = newline

        if original != cleaned:
            missing_final_newline = 1
    else:
        content, ending = lines[-1]

        if ending == b"":
            lines[-1] = (
                content,
                newline,
            )

            missing_final_newline = 1

        cleaned = b"".join(
            content + ending
            for content, ending in lines
        )

    if cleaned != original:
        path.write_bytes(cleaned)

    return (
        trailing_whitespace,
        extra_eof_blank_lines,
        missing_final_newline,
    )


def main() -> int:
    try:
        root = repository_root()
        files = changed_files(root)

    except (
        subprocess.CalledProcessError,
        OSError,
    ) as error:
        print(
            f"ERROR: {error}",
            file=sys.stderr,
        )

        return 1

    scanned = 0
    modified = 0

    total_trailing = 0
    total_eof = 0
    total_missing_newline = 0

    for path in files:
        if not path.is_file():
            continue

        if not is_text_target(
            path,
            root,
        ):
            continue

        scanned += 1

        before = path.read_bytes()

        (
            trailing,
            eof_blank_lines,
            missing_newline,
        ) = clean_file(path)

        after = path.read_bytes()

        if before == after:
            continue

        modified += 1

        total_trailing += trailing
        total_eof += eof_blank_lines
        total_missing_newline += (
            missing_newline
        )

        relative = (
            path
            .relative_to(root)
            .as_posix()
        )

        emit(
            "FIXED",
            relative,
            trailing,
            eof_blank_lines,
            missing_newline,
        )

    emit(
        "SUMMARY",
        scanned,
        modified,
        total_trailing,
        total_eof,
        total_missing_newline,
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
