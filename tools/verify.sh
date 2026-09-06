#!/bin/sh

set -u

echo
echo "========================================"
echo " CPU Router - verification"
echo "========================================"
echo

SCRIPT_DIR=$(
    CDPATH= cd -- "$(dirname -- "$0")" &&
    pwd
)

if [ -z "$SCRIPT_DIR" ]
then
    echo "VERIFY FAILED"
    echo "Could not determine tools directory."
    exit 1
fi

ROOT_DIR=$(
    CDPATH= cd -- "$SCRIPT_DIR/.." &&
    pwd
)

if [ -z "$ROOT_DIR" ]
then
    echo "VERIFY FAILED"
    echo "Could not determine project root."
    exit 1
fi

cd "$ROOT_DIR" || exit 1

if ! command -v g++ >/dev/null 2>&1
then
    echo "VERIFY FAILED"
    echo "g++ was not found in PATH."
    exit 1
fi

BUILD_DIR="build/tests"

mkdir -p "$BUILD_DIR"

TEST_LIST=$(mktemp)

if [ -z "$TEST_LIST" ] || [ ! -f "$TEST_LIST" ]
then
    echo "VERIFY FAILED"
    echo "Could not create temporary test list."
    exit 1
fi

find tests \
    -type f \
    -name '*_test.cpp' \
    -print |
    sort > "$TEST_LIST"

if [ ! -s "$TEST_LIST" ]
then
    echo "VERIFY FAILED"
    echo "No *_test.cpp files were found."
    rm -f "$TEST_LIST"
    exit 1
fi

PROJECT_SOURCES=$(
    find . \
        -maxdepth 1 \
        -type f \
        -name '*.cpp' \
        ! -name 'main.cpp' \
        -print |
    sort
)

test_count=0

while IFS= read -r test_file
do
    test_count=$((test_count + 1))

    test_name=$(
        basename "$test_file" .cpp
    )

    executable="$BUILD_DIR/$test_name.exe"

    echo "----------------------------------------"
    echo "TEST: $test_name"
    echo "----------------------------------------"

    echo "[BUILD] $test_file"

    if ! g++ \
        -std=c++20 \
        -Wall \
        -Wextra \
        -Wpedantic \
        "$test_file" \
        $PROJECT_SOURCES \
        -I. \
        -o "$executable"
    then
        echo
        echo "VERIFY FAILED"
        echo "Build failed: $test_name"
        rm -f "$TEST_LIST"
        exit 1
    fi

    echo "[RUN]   $test_name"

    if ! "$executable"
    then
        echo
        echo "VERIFY FAILED"
        echo "Test failed: $test_name"
        rm -f "$TEST_LIST"
        exit 1
    fi

    echo "[PASS]  $test_name"
    echo
done < "$TEST_LIST"

rm -f "$TEST_LIST"

echo "========================================"
echo " ALL TESTS PASSED"
echo " Tests executed: $test_count"
echo "========================================"
echo

exit 0
