#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$ROOT_DIR" || exit 1

CONSOLE_SH="$ROOT_DIR/tools/lib/console.sh"
if [ ! -f "$CONSOLE_SH" ]; then
    printf 'VERIFY ERROR: tools/lib/console.sh was not found.\n'
    exit 1
fi
. "$CONSOLE_SH"

EMBEDDED=${VERIFY_EMBEDDED:-0}

if [ "$EMBEDDED" != "1" ]; then
    ui_tool_header "VERIFY" "TEST SUITE" "C++20 · -Wall -Wextra -Wpedantic" "$UI_GREEN" "$UI_CYAN"
fi

if ! command -v g++ >/dev/null 2>&1; then
    ui_fail "g++ was not found in PATH."
    [ "$EMBEDDED" = "1" ] || ui_footer_fail "VERIFICATION FAILED"
    exit 1
fi

BUILD_DIR="build/tests"
mkdir -p "$BUILD_DIR"

TEST_LIST=$(mktemp)
BUILD_LOG=$(mktemp)
RUN_LOG=$(mktemp)

if [ ! -f "$TEST_LIST" ] || [ ! -f "$BUILD_LOG" ] || [ ! -f "$RUN_LOG" ]; then
    ui_fail "Could not create temporary verification files."
    rm -f "$TEST_LIST" "$BUILD_LOG" "$RUN_LOG"
    exit 1
fi

cleanup() { rm -f "$TEST_LIST" "$BUILD_LOG" "$RUN_LOG"; }
trap cleanup 0

find tests -type f -name '*_test.cpp' -print | sort > "$TEST_LIST"

if [ ! -s "$TEST_LIST" ]; then
    ui_fail "No *_test.cpp files were found."
    [ "$EMBEDDED" = "1" ] || ui_footer_fail "VERIFICATION FAILED"
    exit 1
fi

PROJECT_SOURCES=$(find . -maxdepth 1 -type f -name '*.cpp' ! -name 'main.cpp' -print | sort)

ui_section "TESTS"
TEST_COUNT=0

while IFS= read -r TEST_FILE
do
    TEST_COUNT=$((TEST_COUNT + 1))
    TEST_NAME=$(basename "$TEST_FILE" .cpp)
    EXECUTABLE="$BUILD_DIR/$TEST_NAME.exe"

    : > "$BUILD_LOG"
    : > "$RUN_LOG"

    if ! g++ -std=c++20 -Wall -Wextra -Wpedantic "$TEST_FILE" $PROJECT_SOURCES -I. -o "$EXECUTABLE" > "$BUILD_LOG" 2>&1; then
        ui_fail "$TEST_NAME · build failed"
        if [ -s "$BUILD_LOG" ]; then
            printf '\n'
            ui_section "COMPILER OUTPUT"
            cat "$BUILD_LOG"
        fi
        [ "$EMBEDDED" = "1" ] || ui_footer_fail "VERIFICATION FAILED"
        exit 1
    fi

    if ! "$EXECUTABLE" > "$RUN_LOG" 2>&1; then
        ui_fail "$TEST_NAME · test failed"
        if [ -s "$RUN_LOG" ]; then
            printf '\n'
            ui_section "TEST OUTPUT"
            cat "$RUN_LOG"
        fi
        [ "$EMBEDDED" = "1" ] || ui_footer_fail "VERIFICATION FAILED"
        exit 1
    fi

    ui_ok "$TEST_NAME"
done < "$TEST_LIST"

printf '\n'
ui_ok "$TEST_COUNT / $TEST_COUNT tests passed"
[ "$EMBEDDED" = "1" ] || ui_footer_ok "VERIFICATION COMPLETE"
exit 0
