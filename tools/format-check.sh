#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT_DIR=${FORMAT_ROOT:-$DEFAULT_ROOT}
QUIET=${FORMAT_CHECK_QUIET:-0}
cd "$ROOT_DIR" || exit 1

CONSOLE_SH="$ROOT_DIR/tools/lib/console.sh"
if [ -f "$CONSOLE_SH" ]; then
    . "$CONSOLE_SH"
else
    ui_ok() { printf '[ OK ] %s\n' "$1"; }
    ui_fail() { printf '[FAIL] %s\n' "$1"; }
fi

if ! command -v clang-format >/dev/null 2>&1; then
    ui_fail "clang-format was not found in PATH."
    exit 1
fi

FILE_LIST=$(mktemp)
if [ ! -f "$FILE_LIST" ]; then
    ui_fail "Could not create temporary file list."
    exit 1
fi
cleanup() { rm -f "$FILE_LIST"; }
trap cleanup 0

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -z '*.c' '*.cpp' '*.h' '*.hpp' > "$FILE_LIST"
else
    find . -type f \( -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) -print0 > "$FILE_LIST"
fi

FAILED=0
SCANNED=0

while IFS= read -r -d '' FILE
do
    [ -f "$FILE" ] || continue
    SCANNED=$((SCANNED + 1))
    FORMATTED=$(mktemp)

    if [ ! -f "$FORMATTED" ]; then
        ui_fail "Could not create temporary formatted file."
        exit 1
    fi

    if ! clang-format --style=file "$FILE" > "$FORMATTED"; then
        rm -f "$FORMATTED"
        ui_fail "clang-format failed: $FILE"
        exit 1
    fi

    if ! cmp -s "$FILE" "$FORMATTED"; then
        ui_fail "Not clang-formatted: $FILE"
        FAILED=1
    fi

    rm -f "$FORMATTED"
done < "$FILE_LIST"

if [ "$FAILED" -ne 0 ]; then
    ui_fail "clang-format check failed."
    exit 1
fi

[ "$QUIET" = "1" ] || ui_ok "clang-format clean · $SCANNED files"
exit 0
