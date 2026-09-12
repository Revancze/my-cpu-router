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

ui_mrproper_banner

ui_section "C++ FORMAT"

if ! sh "$ROOT_DIR/tools/format.sh" --changed
then
    ui_fail "C++ formatting failed."
    exit 1
fi

printf '\n'

if command -v python >/dev/null 2>&1
then
    PYTHON=python
elif command -v python3 >/dev/null 2>&1
then
    PYTHON=python3
else
    ui_fail "Python was not found in PATH."
    exit 1
fi

RESULT_FILE=$(mktemp)

if [ -z "$RESULT_FILE" ] || [ ! -f "$RESULT_FILE" ]
then
    ui_fail "Could not create temporary result file."
    exit 1
fi

if ! "$PYTHON" \
    "$ROOT_DIR/tools/mrproper.py" \
    > "$RESULT_FILE"
then
    ui_fail "Cleanup engine failed."
    rm -f "$RESULT_FILE"
    exit 1
fi

TAB=$(printf '\t')

while IFS="$TAB" read -r kind a b c d e
do
    case "$kind" in
        FIXED)
            ui_fixed "$a"

            if [ "$b" -gt 0 ]
            then
                printf '        trailing whitespace ..... %s\n' "$b"
            fi

            if [ "$c" -gt 0 ]
            then
                printf '        extra EOF blank lines ... %s\n' "$c"
            fi

            if [ "$d" -gt 0 ]
            then
                printf '        final newline added ..... yes\n'
            fi
            ;;

        SUMMARY)
            printf '\n'
            ui_section "SUMMARY"

            printf '  files scanned ................ %s\n' "$a"
            printf '  files modified ............... %s\n' "$b"
            printf '  whitespace lines cleaned ..... %s\n' "$c"
            printf '  EOF blank lines removed ...... %s\n' "$d"
            printf '  final newlines added ......... %s\n' "$e"

            printf '\n'

            if [ "$b" -eq 0 ]
            then
                ui_ok "Working tree already clean."
            else
                ui_ok "Working tree cleaned."
                ui_info "Review changes before staging."
            fi
            ;;
    esac
done < "$RESULT_FILE"

rm -f "$RESULT_FILE"

printf '\n'
exit 0
