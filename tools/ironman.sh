#!/bin/sh

set -u

SCRIPT_DIR=$(
    CDPATH= cd -- "$(dirname -- "$0")" &&
    pwd
)

DEFAULT_ROOT=$(
    CDPATH= cd -- "$SCRIPT_DIR/.." &&
    pwd
)

ROOT_DIR=${IRONMAN_ROOT:-$DEFAULT_ROOT}
SNAPSHOT_MODE=${IRONMAN_SNAPSHOT_MODE:-0}

cd "$ROOT_DIR" || exit 1

CONSOLE_SH="$ROOT_DIR/tools/lib/console.sh"

if [ ! -f "$CONSOLE_SH" ]
then
    printf 'IRONMAN ERROR: tools/lib/console.sh was not found.\n'
    exit 1
fi

# shellcheck source=tools/lib/console.sh
. "$CONSOLE_SH"

ui_ironman_banner

ui_section "ENVIRONMENT"

if ! command -v g++ >/dev/null 2>&1
then
    ui_fail "g++ was not found in PATH."
    exit 1
fi

COMPILER_VERSION=$(
    g++ --version |
    head -n 1
)

ui_ok "$COMPILER_VERSION"
ui_info "C++ standard: C++20"
ui_info "Warnings: -Wall -Wextra -Wpedantic"

if [ ! -f "$ROOT_DIR/tools/verify.sh" ]
then
    ui_fail "tools/verify.sh was not found."
    exit 1
fi

STATUS_BEFORE=""

if [ "$SNAPSHOT_MODE" = "1" ]
then
    ui_info "Snapshot mode enabled."
else
    if ! command -v git >/dev/null 2>&1
    then
        ui_fail "Git was not found in PATH."
        exit 1
    fi

    ui_ok "Git available."

    printf '\n'
    ui_section "SOURCE INTEGRITY"

    STATUS_BEFORE=$(
        git status \
            --porcelain=v1 \
            --untracked-files=all
    )

    ui_ok "Captured Git state before verification."
fi

printf '\n'
ui_section "BUILD AND TEST"

if sh "$ROOT_DIR/tools/verify.sh"
then
    VERIFY_RESULT=0
else
    VERIFY_RESULT=$?
fi

if [ "$SNAPSHOT_MODE" != "1" ]
then
    printf '\n'
    ui_section "SOURCE INTEGRITY"

    STATUS_AFTER=$(
        git status \
            --porcelain=v1 \
            --untracked-files=all
    )

    if [ "$STATUS_BEFORE" != "$STATUS_AFTER" ]
    then
        ui_fail "Verification changed the Git working tree."

        printf '\n'
        printf '%bGit state BEFORE:%b\n' \
            "$UI_YELLOW" \
            "$UI_RESET"

        printf '%s\n' "$STATUS_BEFORE"

        printf '\n'
        printf '%bGit state AFTER:%b\n' \
            "$UI_RED" \
            "$UI_RESET"

        printf '%s\n' "$STATUS_AFTER"

        printf '\n'
        ui_fail "IRONMAN INTEGRITY VIOLATION"

        exit 1
    fi

    ui_ok "Git working tree unchanged."
fi

if [ "$VERIFY_RESULT" -ne 0 ]
then
    printf '\n'

    ui_banner \
        "IRONMAN :: VERIFICATION FAILED" \
        "$UI_RED" \
        "$UI_YELLOW"

    ui_fail "Build or tests failed."

    exit "$VERIFY_RESULT"
fi

printf '\n'

ui_banner \
    "IRONMAN :: ALL SYSTEMS NOMINAL" \
    "$UI_RED" \
    "$UI_YELLOW"

ui_ok "Build passed."
ui_ok "Tests passed."

if [ "$SNAPSHOT_MODE" = "1" ]
then
    ui_ok "Staged snapshot verified."
else
    ui_ok "Source integrity preserved."
fi

printf '\n'

exit 0
