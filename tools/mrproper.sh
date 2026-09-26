#!/bin/sh
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

ui_tool_header "MRPROPER" "WORKTREE CLEANUP" "whitespace · EOF" "$UI_CYAN" "$UI_GREEN"

if command -v python >/dev/null 2>&1; then
    PYTHON=python
elif command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
else
    ui_fail "Python was not found in PATH."
    ui_footer_fail "CLEANUP FAILED"
    exit 1
fi

RESULT_FILE=$(codelaxy_temp_file mrproper-result)
if [ ! -f "$RESULT_FILE" ]; then
    ui_fail "Could not create temporary result file."
    ui_footer_fail "CLEANUP FAILED"
    exit 1
fi

cleanup() {
    rm -f "$RESULT_FILE"
    codelaxy_runtime_cleanup
}
trap cleanup 0

if ! codelaxy_native_exec \
    "$PYTHON" "$ROOT_DIR/tools/mrproper.py" > "$RESULT_FILE"
then
    ui_fail "Cleanup engine failed."
    ui_footer_fail "CLEANUP FAILED"
    exit 1
fi

TAB=$(printf '\t')
FILES_SCANNED=0
FILES_MODIFIED=0
WHITESPACE_CLEANED=0
EOF_BLANKS_REMOVED=0
FINAL_NEWLINES_ADDED=0

printf '\n'
ui_section "CLEANUP"

while IFS="$TAB" read -r KIND A B C D E
do
    case "$KIND" in
        FIXED)
            ui_fixed "$A"
            [ "$B" -gt 0 ] && ui_muted "trailing whitespace · $B"
            [ "$C" -gt 0 ] && ui_muted "EOF blank lines removed · $C"
            [ "$D" -gt 0 ] && ui_muted "final newline added"
            ;;
        SUMMARY)
            FILES_SCANNED=$A
            FILES_MODIFIED=$B
            WHITESPACE_CLEANED=$C
            EOF_BLANKS_REMOVED=$D
            FINAL_NEWLINES_ADDED=$E
            ;;
    esac
done < "$RESULT_FILE"

if [ "$FILES_MODIFIED" -eq 0 ]; then
    ui_ok "No cleanup changes required."
else
    printf '\n'
    ui_metric "files modified" "$FILES_MODIFIED"
    [ "$WHITESPACE_CLEANED" -gt 0 ] && ui_metric "whitespace lines" "$WHITESPACE_CLEANED"
    [ "$EOF_BLANKS_REMOVED" -gt 0 ] && ui_metric "EOF blank lines" "$EOF_BLANKS_REMOVED"
    [ "$FINAL_NEWLINES_ADDED" -gt 0 ] && ui_metric "final newlines" "$FINAL_NEWLINES_ADDED"
fi

if [ "$FILES_MODIFIED" -eq 0 ]; then
    ui_footer_ok "WORKTREE CLEAN · $FILES_SCANNED files scanned"
else
    ui_footer_ok "WORKTREE CLEANED · review before staging"
fi
exit 0
