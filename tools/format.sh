#!/bin/sh

set -u

SCRIPT_DIR=$(
    CDPATH= cd -- "$(dirname -- "$0")" &&
    pwd
)

ROOT_DIR=$(
    CDPATH= cd -- "$SCRIPT_DIR/.." &&
    pwd
)

cd "$ROOT_DIR" || exit 1

# shellcheck source=tools/lib/console.sh
. "$ROOT_DIR/tools/lib/console.sh"

if ! command -v clang-format >/dev/null 2>&1
then
    ui_fail "clang-format was not found in PATH."
    exit 1
fi

MODE=${1:-changed}

case "$MODE" in
    changed|--changed)
        MODE=changed
        ;;

    all|--all)
        MODE=all
        ;;

    *)
        ui_fail "Usage: sh tools/format.sh [--changed|--all]"
        exit 1
        ;;
esac

FILE_LIST=$(mktemp)

if [ -z "$FILE_LIST" ] ||
   [ ! -f "$FILE_LIST" ]
then
    ui_fail "Could not create temporary file list."
    exit 1
fi

cleanup()
{
    rm -f "$FILE_LIST"
}

trap cleanup 0

if [ "$MODE" = "all" ]
then
    git ls-files \
        -z \
        '*.c' \
        '*.cpp' \
        '*.h' \
        '*.hpp' \
        > "$FILE_LIST"
else
    {
        git diff \
            --name-only \
            -z \
            HEAD \
            -- \
            '*.c' \
            '*.cpp' \
            '*.h' \
            '*.hpp'

        git ls-files \
            --others \
            --exclude-standard \
            -z \
            -- \
            '*.c' \
            '*.cpp' \
            '*.h' \
            '*.hpp'
    } > "$FILE_LIST"
fi

SCANNED=0
FORMATTED=0

while IFS= read -r -d '' FILE
do
    if [ ! -f "$FILE" ]
    then
        continue
    fi

    SCANNED=$((SCANNED + 1))

    BEFORE=$(mktemp)

    if [ -z "$BEFORE" ] ||
       [ ! -f "$BEFORE" ]
    then
        ui_fail "Could not create temporary comparison file."
        exit 1
    fi

    cp -- "$FILE" "$BEFORE"

    if ! clang-format \
        -i \
        --style=file \
        "$FILE"
    then
        rm -f "$BEFORE"
        ui_fail "clang-format failed: $FILE"
        exit 1
    fi

    if ! cmp -s "$BEFORE" "$FILE"
    then
        ui_fixed "$FILE"
        FORMATTED=$((FORMATTED + 1))
    fi

    rm -f "$BEFORE"
done < "$FILE_LIST"

printf '  C++ files scanned ............. %s\n' "$SCANNED"
printf '  C++ files formatted ........... %s\n' "$FORMATTED"

exit 0
