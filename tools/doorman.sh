#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$ROOT_DIR" || exit 1
. "$ROOT_DIR/tools/lib/console.sh"
. "$ROOT_DIR/tools/lib/runtime.sh"

if ! codelaxy_runtime_init; then
    ui_fail "Could not initialize Codelaxy runtime."
    exit 1
fi

trap codelaxy_runtime_cleanup 0

deny() {
    ui_footer_fail "ACCESS DENIED"
    exit "${1:-1}"
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ui_tool_header "DOORMAN" "COMMIT GATE" "not a Git repository" "$UI_BLUE" "$UI_MAGENTA"
    ui_fail "Not inside a Git repository."
    deny 1
fi

BRANCH=$(git branch --show-current)
[ -n "$BRANCH" ] || BRANCH="detached HEAD"

ui_tool_header "DOORMAN" "COMMIT GATE" "$BRANCH" "$UI_BLUE" "$UI_MAGENTA"
ui_section "STAGED"

if git diff --cached --quiet --exit-code; then
    ui_fail "No staged changes."
    deny 1
fi

ui_ok "Changes detected."
STATUS_BEFORE=$(git status --porcelain=v1 --untracked-files=all)

if ! git diff --cached --check; then
    ui_fail "Whitespace errors detected."
    deny 1
fi
ui_ok "Whitespace clean."

FILE_LIST=$(codelaxy_temp_file doorman-files)
if [ ! -f "$FILE_LIST" ]; then
    ui_fail "Could not create temporary file list."
    deny 1
fi

SNAPSHOT_DIR=""
FORMAT_LOG=""

cleanup() {
    rm -f "$FILE_LIST"
    [ -z "$FORMAT_LOG" ] || rm -f "$FORMAT_LOG"
    [ -z "$SNAPSHOT_DIR" ] || rm -rf "$SNAPSHOT_DIR"
    codelaxy_runtime_cleanup
}
trap cleanup 0

git diff --cached --name-only --diff-filter=ACMR -z > "$FILE_LIST"

NEWLINE_FAILED=0
while IFS= read -r -d '' FILE
do
    case "$FILE" in
        *.cpp|*.hpp|*.h|*.c|*.json|*.md|*.py|*.sh|*.cmd|*.bat|.editorconfig|.gitattributes|.gitignore|githooks/*) ;;
        *) continue ;;
    esac

    if ! git cat-file -e ":$FILE" 2>/dev/null; then
        continue
    fi

    LAST_BYTE=$(git show ":$FILE" | tail -c 1 | od -An -t x1 | tr -d ' \n')

    if [ "$LAST_BYTE" != "0a" ]; then
        ui_fail "No final newline: $FILE"
        NEWLINE_FAILED=1
    fi
done < "$FILE_LIST"

[ "$NEWLINE_FAILED" -eq 0 ] || deny 1
ui_ok "Final newlines clean."

SNAPSHOT_DIR=$(codelaxy_snapshot_dir doorman-staged)
if [ ! -d "$SNAPSHOT_DIR" ]; then
    ui_fail "Could not create staged snapshot."
    deny 1
fi

if ! git checkout-index --all --force --prefix="$SNAPSHOT_DIR/"; then
    ui_fail "Could not create staged snapshot."
    deny 1
fi
ui_ok "Snapshot created."

if [ ! -f "$SNAPSHOT_DIR/tools/format-check.sh" ]; then
    ui_fail "Snapshot is missing tools/format-check.sh."
    deny 1
fi

if [ ! -f "$SNAPSHOT_DIR/.clang-format" ]; then
    ui_fail "Snapshot is missing .clang-format."
    deny 1
fi

FORMAT_LOG=$(codelaxy_temp_file doorman-format)
if [ ! -f "$FORMAT_LOG" ]; then
    ui_fail "Could not create format-check log."
    deny 1
fi

if ! CODELAXY_RUNTIME_ROOT="$CODELAXY_RUNTIME_BASE" \
    FORMAT_ROOT="$SNAPSHOT_DIR" \
    FORMAT_CHECK_QUIET=1 \
    bash "$SNAPSHOT_DIR/tools/format-check.sh" > "$FORMAT_LOG" 2>&1
then
    ui_fail "clang-format check failed."
    [ ! -s "$FORMAT_LOG" ] || cat "$FORMAT_LOG"
    deny 1
fi
ui_ok "clang-format clean."

if [ ! -f "$SNAPSHOT_DIR/tools/ironman.sh" ]; then
    ui_fail "Snapshot is missing tools/ironman.sh."
    deny 1
fi

printf '\n'
if ! CODELAXY_RUNTIME_ROOT="$CODELAXY_RUNTIME_BASE" \
    IRONMAN_ROOT="$SNAPSHOT_DIR" \
    IRONMAN_SNAPSHOT_MODE=1 \
    IRONMAN_EMBEDDED=1 \
    bash "$SNAPSHOT_DIR/tools/ironman.sh"
then
    printf '\n'
    ui_fail "IronMan rejected the staged snapshot."
    deny 1
fi

STATUS_AFTER=$(git status --porcelain=v1 --untracked-files=all)

if [ "$STATUS_BEFORE" != "$STATUS_AFTER" ]; then
    printf '\n'
    ui_section "INTEGRITY"
    ui_fail "Doorman changed repository state."
    deny 1
fi

printf '\n'
ui_ok "Repository state unchanged."
ui_footer_ok "ACCESS GRANTED · commit allowed"
exit 0
