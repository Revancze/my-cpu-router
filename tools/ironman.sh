#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT_DIR=${IRONMAN_ROOT:-$DEFAULT_ROOT}
SNAPSHOT_MODE=${IRONMAN_SNAPSHOT_MODE:-0}
EMBEDDED=${IRONMAN_EMBEDDED:-0}
cd "$ROOT_DIR" || exit 1

CONSOLE_SH="$ROOT_DIR/tools/lib/console.sh"
if [ ! -f "$CONSOLE_SH" ]; then
    printf 'IRONMAN ERROR: tools/lib/console.sh was not found.\n'
    exit 1
fi
. "$CONSOLE_SH"
. "$ROOT_DIR/tools/lib/runtime.sh"

if ! codelaxy_runtime_init; then
    ui_fail "Could not initialize Codelaxy runtime."
    exit 1
fi

trap codelaxy_runtime_cleanup 0

if ! command -v g++ >/dev/null 2>&1; then
    [ "$EMBEDDED" = "1" ] && ui_section "IRONMAN" || ui_ironman_banner
    ui_fail "g++ was not found in PATH."
    exit 1
fi

COMPILER_VERSION=$(codelaxy_native_exec g++ --version | head -n 1)

if [ "$EMBEDDED" = "1" ]; then
    ui_section "IRONMAN"
else
    ui_tool_header "IRONMAN" "VERIFICATION SUITE" "C++20 · -Wall -Wextra -Wpedantic" "$UI_RED" "$UI_YELLOW"
fi

ui_info "$COMPILER_VERSION"
[ "$SNAPSHOT_MODE" = "1" ] && ui_muted "staged snapshot mode"

if [ ! -f "$ROOT_DIR/tools/verify.sh" ]; then
    ui_fail "tools/verify.sh was not found."
    exit 1
fi

STATUS_BEFORE=""
if [ "$SNAPSHOT_MODE" != "1" ]; then
    if ! command -v git >/dev/null 2>&1; then
        ui_fail "Git was not found in PATH."
        exit 1
    fi
    STATUS_BEFORE=$(git status --porcelain=v1 --untracked-files=all)
fi

printf '\n'
if CODELAXY_RUNTIME_ROOT="$CODELAXY_RUNTIME_BASE" \
    VERIFY_EMBEDDED=1 \
    bash "$ROOT_DIR/tools/verify.sh"
then
    VERIFY_RESULT=0
else
    VERIFY_RESULT=$?
fi

if [ "$VERIFY_RESULT" -ne 0 ]; then
    if [ "$EMBEDDED" = "1" ]; then
        printf '\n'
        ui_fail "IronMan rejected the build or tests."
    else
        ui_footer_fail "VERIFICATION FAILED"
    fi
    exit "$VERIFY_RESULT"
fi

if [ "$SNAPSHOT_MODE" != "1" ]; then
    STATUS_AFTER=$(git status --porcelain=v1 --untracked-files=all)
    if [ "$STATUS_BEFORE" != "$STATUS_AFTER" ]; then
        printf '\n'
        ui_section "INTEGRITY"
        ui_fail "Verification changed the Git working tree."
        printf '\n%bBEFORE%b\n%s\n' "$UI_YELLOW" "$UI_RESET" "$STATUS_BEFORE"
        printf '\n%bAFTER%b\n%s\n' "$UI_RED" "$UI_RESET" "$STATUS_AFTER"
        [ "$EMBEDDED" = "1" ] && ui_fail "IronMan integrity violation." || ui_footer_fail "INTEGRITY VIOLATION"
        exit 1
    fi
fi

printf '\n'
[ "$SNAPSHOT_MODE" = "1" ] && ui_ok "Staged snapshot verified." || ui_ok "Source integrity preserved."

if [ "$EMBEDDED" = "1" ]; then
    ui_ok "IronMan nominal."
else
    ui_footer_ok "ALL SYSTEMS NOMINAL"
fi
exit 0
