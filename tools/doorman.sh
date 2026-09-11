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

ui_doorman_banner

ui_section "REPOSITORY"

if ! git rev-parse \
    --is-inside-work-tree \
    >/dev/null 2>&1
then
    ui_fail "Not inside a Git repository."
    exit 1
fi

ui_ok "Git repository detected."

BRANCH=$(
    git branch --show-current
)

if [ -n "$BRANCH" ]
then
    ui_info "Branch: $BRANCH"
else
    ui_info "Detached HEAD."
fi

if git diff \
    --cached \
    --quiet \
    --exit-code
then
    ui_fail "No staged changes."

    printf '\n'

    ui_banner \
        "DOORMAN :: ACCESS DENIED" \
        "$UI_RED" \
        "$UI_YELLOW"

    exit 1
fi

ui_ok "Staged changes detected."

STATUS_BEFORE=$(
    git status \
        --porcelain=v1 \
        --untracked-files=all
)

printf '\n'
ui_section "STAGED CHECKS"

if ! git diff --cached --check
then
    ui_fail "Staged whitespace errors detected."

    printf '\n'

    ui_banner \
        "DOORMAN :: ACCESS DENIED" \
        "$UI_RED" \
        "$UI_YELLOW"

    exit 1
fi

ui_ok "Staged whitespace clean."

FILE_LIST=$(mktemp)

if [ -z "$FILE_LIST" ] ||
   [ ! -f "$FILE_LIST" ]
then
    ui_fail "Could not create temporary file list."
    exit 1
fi

cleanup_file_list()
{
    rm -f "$FILE_LIST"
}

trap cleanup_file_list 0

git diff \
    --cached \
    --name-only \
    --diff-filter=ACMR \
    -z \
    > "$FILE_LIST"

NEWLINE_FAILED=0

while IFS= read -r -d '' FILE
do
    case "$FILE" in
        *.cpp|*.hpp|*.h|*.c|*.json|*.md|*.py|*.sh|*.cmd|*.bat|\
        .editorconfig|.gitattributes|.gitignore|githooks/*)
            ;;
        *)
            continue
            ;;
    esac

    if ! git cat-file \
        -e ":$FILE" \
        2>/dev/null
    then
        continue
    fi

    LAST_BYTE=$(
        git show ":$FILE" |
        tail -c 1 |
        od -An -t x1 |
        tr -d ' \n'
    )

    if [ "$LAST_BYTE" != "0a" ]
    then
        ui_fail "No final newline: $FILE"
        NEWLINE_FAILED=1
    fi
done < "$FILE_LIST"

if [ "$NEWLINE_FAILED" -ne 0 ]
then
    printf '\n'

    ui_banner \
        "DOORMAN :: ACCESS DENIED" \
        "$UI_RED" \
        "$UI_YELLOW"

    exit 1
fi

ui_ok "Staged final newlines clean."

printf '\n'
ui_section "STAGED SNAPSHOT"

SNAPSHOT_DIR=$(mktemp -d)

if [ -z "$SNAPSHOT_DIR" ] ||
   [ ! -d "$SNAPSHOT_DIR" ]
then
    ui_fail "Could not create staged snapshot directory."
    exit 1
fi

cleanup_all()
{
    rm -f "$FILE_LIST"
    rm -rf "$SNAPSHOT_DIR"
}

trap cleanup_all 0

if ! git checkout-index \
    --all \
    --force \
    --prefix="$SNAPSHOT_DIR/"
then
    ui_fail "Could not create staged snapshot."
    exit 1
fi

ui_ok "Staged snapshot created."

if [ ! -f "$SNAPSHOT_DIR/tools/ironman.sh" ]
then
    ui_fail "Staged snapshot does not contain tools/ironman.sh."
    exit 1
fi

printf '\n'
ui_section "SUMMONING IRONMAN"

if ! IRONMAN_ROOT="$SNAPSHOT_DIR" \
    IRONMAN_SNAPSHOT_MODE=1 \
    sh "$SNAPSHOT_DIR/tools/ironman.sh"
then
    printf '\n'

    ui_fail "IronMan rejected the staged snapshot."

    printf '\n'

    ui_banner \
        "DOORMAN :: ACCESS DENIED" \
        "$UI_RED" \
        "$UI_YELLOW"

    exit 1
fi

printf '\n'
ui_section "INTEGRITY"

STATUS_AFTER=$(
    git status \
        --porcelain=v1 \
        --untracked-files=all
)

if [ "$STATUS_BEFORE" != "$STATUS_AFTER" ]
then
    ui_fail "Doorman changed repository state."

    printf '\n'

    ui_banner \
        "DOORMAN :: ACCESS DENIED" \
        "$UI_RED" \
        "$UI_YELLOW"

    exit 1
fi

ui_ok "Repository state unchanged."

printf '\n'

ui_banner \
    "DOORMAN :: ACCESS GRANTED" \
    "$UI_GREEN" \
    "$UI_CYAN"

ui_ok "Staged changes verified."
ui_ok "Commit allowed."

printf '\n'

exit 0
