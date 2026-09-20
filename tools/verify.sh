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
. "$ROOT_DIR/tools/lib/runtime.sh"

if ! codelaxy_runtime_init; then
    ui_fail "Could not initialize Codelaxy runtime."
    exit 1
fi

trap codelaxy_runtime_cleanup 0

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

TEST_LIST=$(codelaxy_temp_file verify-cpp-tests)
PYTHON_TEST_LIST=$(codelaxy_temp_file verify-python-tests)
BUILD_LOG=$(codelaxy_temp_file verify-build)
RUN_LOG=$(codelaxy_temp_file verify-run)

if [ ! -f "$TEST_LIST" ] || [ ! -f "$PYTHON_TEST_LIST" ] ||
   [ ! -f "$BUILD_LOG" ] || [ ! -f "$RUN_LOG" ]; then
    ui_fail "Could not create temporary verification files."
    rm -f "$TEST_LIST" "$PYTHON_TEST_LIST" "$BUILD_LOG" "$RUN_LOG"
    exit 1
fi

cleanup() {
    rm -f "$TEST_LIST" "$PYTHON_TEST_LIST" "$BUILD_LOG" "$RUN_LOG"
    codelaxy_runtime_cleanup
}
trap cleanup 0

find tests -type f -name '*_test.cpp' -print | sort > "$TEST_LIST"
find tests -type f -name '*_test.py' -print | sort > "$PYTHON_TEST_LIST"

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

    if ! codelaxy_native_exec \
        g++ -std=c++20 -Wall -Wextra -Wpedantic \
        "$TEST_FILE" $PROJECT_SOURCES -I. -o "$EXECUTABLE" \
        > "$BUILD_LOG" 2>&1
    then
        ui_fail "$TEST_NAME · build failed"
        if [ -s "$BUILD_LOG" ]; then
            printf '\n'
            ui_section "COMPILER OUTPUT"
            cat "$BUILD_LOG"
        fi
        [ "$EMBEDDED" = "1" ] || ui_footer_fail "VERIFICATION FAILED"
        exit 1
    fi

    if ! codelaxy_native_exec "$EXECUTABLE" > "$RUN_LOG" 2>&1
    then
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

if [ -s "$PYTHON_TEST_LIST" ]; then
    if command -v python >/dev/null 2>&1; then
        PYTHON=python
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON=python3
    else
        ui_fail "Python was not found in PATH."
        [ "$EMBEDDED" = "1" ] || ui_footer_fail "VERIFICATION FAILED"
        exit 1
    fi

    printf '\n'
    ui_section "TOOLING TESTS"
    PYTHON_TEST_COUNT=0

    while IFS= read -r PYTHON_TEST_FILE
    do
        PYTHON_TEST_COUNT=$((PYTHON_TEST_COUNT + 1))
        PYTHON_TEST_NAME=$(basename "$PYTHON_TEST_FILE" .py)

        : > "$RUN_LOG"

        if ! PYTHONDONTWRITEBYTECODE=1 \
            PYTHONPATH="$ROOT_DIR${PYTHONPATH:+:$PYTHONPATH}" \
            codelaxy_native_exec \
            "$PYTHON" "$PYTHON_TEST_FILE" > "$RUN_LOG" 2>&1
        then
            ui_fail "$PYTHON_TEST_NAME · test failed"
            if [ -s "$RUN_LOG" ]; then
                printf '\n'
                ui_section "TEST OUTPUT"
                cat "$RUN_LOG"
            fi
            [ "$EMBEDDED" = "1" ] || ui_footer_fail "VERIFICATION FAILED"
            exit 1
        fi

        ui_ok "$PYTHON_TEST_NAME"
    done < "$PYTHON_TEST_LIST"

    printf '\n'
    ui_ok "$PYTHON_TEST_COUNT / $PYTHON_TEST_COUNT tooling tests passed"
fi

[ "$EMBEDDED" = "1" ] || ui_footer_ok "VERIFICATION COMPLETE"
exit 0
