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

ROOT_DIR=${FORMAT_ROOT:-$DEFAULT_ROOT}

cd "$ROOT_DIR" || exit 1

if ! command -v clang-format >/dev/null 2>&1
then
    printf '[FAIL] clang-format was not found in PATH.\n'
    exit 1
fi

FILE_LIST=$(mktemp)

if [ -z "$FILE_LIST" ] ||
   [ ! -f "$FILE_LIST" ]
then
    printf '[FAIL] Could not create temporary file list.\n'
    exit 1
fi

cleanup()
{
    rm -f "$FILE_LIST"
}

trap cleanup 0

if git rev-parse \
    --is-inside-work-tree \
    >/dev/null 2>&1
then
    git ls-files \
        -z \
        '*.c' \
        '*.cpp' \
        '*.h' \
        '*.hpp' \
        > "$FILE_LIST"
else
    find . \
        -type f \
        \( \
            -name '*.c' -o \
            -name '*.cpp' -o \
            -name '*.h' -o \
            -name '*.hpp' \
        \) \
        -print0 \
        > "$FILE_LIST"
fi

FAILED=0
SCANNED=0

while IFS= read -r -d '' FILE
do
    if [ ! -f "$FILE" ]
    then
        continue
    fi

    SCANNED=$((SCANNED + 1))

    FORMATTED=$(mktemp)

    if [ -z "$FORMATTED" ] ||
       [ ! -f "$FORMATTED" ]
    then
        printf '[FAIL] Could not create temporary formatted file.\n'
        exit 1
    fi

    if ! clang-format \
        --style=file \
        "$FILE" \
        > "$FORMATTED"
    then
        rm -f "$FORMATTED"
        printf '[FAIL] clang-format failed: %s\n' "$FILE"
        exit 1
    fi

    if ! cmp -s "$FILE" "$FORMATTED"
    then
        printf '[FAIL] Not clang-formatted: %s\n' "$FILE"
        FAILED=1
    fi

    rm -f "$FORMATTED"
done < "$FILE_LIST"

if [ "$FAILED" -ne 0 ]
then
    printf '[FAIL] clang-format check failed.\n'
    exit 1
fi

printf '[ OK ] clang-format clean (%s files).\n' "$SCANNED"

exit 0
