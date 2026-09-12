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

CONSOLE_SH="$ROOT_DIR/tools/lib/console.sh"

if [ ! -f "$CONSOLE_SH" ]
then
    printf 'STATUSMAN ERROR: tools/lib/console.sh was not found.\n'
    exit 1
fi

# shellcheck source=tools/lib/console.sh
. "$CONSOLE_SH"

# ============================================================
# HELPERS
# ============================================================

is_line_range()
{
    case "$1" in
        [0-9]*-[0-9]*|[0-9]*-|-[0-9]*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

resolve_range()
{
    RANGE_VALUE=$1
    FILE_LINES=$2

    RANGE_START=1
    RANGE_END=$FILE_LINES

    case "$RANGE_VALUE" in
        -*)
            RANGE_END=${RANGE_VALUE#-}
            ;;
        *-)
            RANGE_START=${RANGE_VALUE%-}
            ;;
        *-*)
            RANGE_START=${RANGE_VALUE%-*}
            RANGE_END=${RANGE_VALUE#*-}
            ;;
    esac

    case "$RANGE_START" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    case "$RANGE_END" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    if [ "$RANGE_START" -lt 1 ] ||
       [ "$RANGE_END" -lt 1 ]
    then
        return 1
    fi

    case "$RANGE_VALUE" in
        *-)
            if [ "$RANGE_START" -gt "$FILE_LINES" ]
            then
                return 0
            fi
            ;;
        *)
            if [ "$RANGE_START" -gt "$RANGE_END" ]
            then
                return 1
            fi
            ;;
    esac

    if [ "$RANGE_END" -gt "$FILE_LINES" ]
    then
        RANGE_END=$FILE_LINES
    fi

    return 0
}

queue_warning()
{
    printf '%s\n' "$1" >> "$WARNINGS_FILE"
}

add_inspection_file()
{
    FILE=$1

    if grep -Fqx "$FILE" "$INSPECTION_FILES" 2>/dev/null
    then
        return
    fi

    printf '%s\n' "$FILE" >> "$INSPECTION_FILES"
}

resolve_file_argument()
{
    ARG=$1
    MATCHED=0

    if [ -f "$ARG" ]
    then
        add_inspection_file "$ARG"
        return
    fi

    while IFS= read -r CANDIDATE
    do
        case "$CANDIDATE" in
            $ARG)
                add_inspection_file "$CANDIDATE"
                MATCHED=1
                ;;
        esac
    done < "$AVAILABLE_FILES"

    if [ "$MATCHED" -eq 0 ]
    then
        queue_warning "No file matches: $ARG"
    fi
}

render_name_status()
{
    MODE=$1

    if [ "$MODE" = "staged" ]
    then
        git diff --cached --name-status
    else
        git diff --name-status
    fi |
    while IFS="$(printf '\t')" read -r KIND FILE REST
    do
        case "$KIND" in
            A)
                ui_change add "$FILE  [$MODE]"
                ;;
            D)
                ui_change delete "$FILE  [$MODE]"
                ;;
            M|R*|C*|T)
                ui_change modify "$FILE  [$MODE]"
                ;;
            U*)
                ui_warn "$FILE  [conflict]"
                ;;
            *)
                printf '  %s\t%s\n' "$KIND" "$FILE"
                ;;
        esac
    done
}

render_untracked()
{
    git ls-files --others --exclude-standard |
    while IFS= read -r FILE
    do
        printf '%b?%b %s  %b[untracked]%b\n' \
            "$UI_CYAN" \
            "$UI_RESET" \
            "$FILE" \
            "$UI_DIM" \
            "$UI_RESET"
    done
}

render_conflicts()
{
    git diff --name-only --diff-filter=U |
    while IFS= read -r FILE
    do
        ui_warn "$FILE  [conflict]"
    done
}

render_diff_summary()
{
    MODE=$1

    if [ "$MODE" = "staged" ]
    then
        if git diff --cached --check >/dev/null 2>&1
        then
            CHECK_TEXT="whitespace ✓"
            CHECK_COLOR=$UI_GREEN
        else
            CHECK_TEXT="whitespace !"
            CHECK_COLOR=$UI_YELLOW
        fi

        STAT_TEXT=$(
            git diff --cached --stat |
            tail -n 1
        )
    else
        if git diff --check >/dev/null 2>&1
        then
            CHECK_TEXT="whitespace ✓"
            CHECK_COLOR=$UI_GREEN
        else
            CHECK_TEXT="whitespace !"
            CHECK_COLOR=$UI_YELLOW
        fi

        STAT_TEXT=$(
            git diff --stat |
            tail -n 1
        )
    fi

    if [ -z "$STAT_TEXT" ]
    then
        STAT_TEXT="no diff statistics"
    fi

    printf '  %-9s  %b%-14s%b  %s\n' \
        "$MODE" \
        "$CHECK_COLOR" \
        "$CHECK_TEXT" \
        "$UI_RESET" \
        "$STAT_TEXT"
}

render_file()
{
    FILE=$1
    REQUESTED_RANGE=$2

    if [ ! -f "$FILE" ]
    then
        ui_warn "File does not exist: $FILE"
        return
    fi

    FILE_LINES=$(
        awk 'END { print NR + 0 }' "$FILE"
    )

    RANGE_START=1
    RANGE_END=$FILE_LINES

    if [ -n "$REQUESTED_RANGE" ]
    then
        if ! resolve_range "$REQUESTED_RANGE" "$FILE_LINES"
        then
            ui_warn "Invalid line range '$REQUESTED_RANGE' for $FILE"
            return
        fi
    fi

    if [ "$FILE_LINES" -eq 0 ]
    then
        printf '\n'
        ui_section "$FILE"
        ui_muted "empty file"
        return
    fi

    if [ "$RANGE_START" -gt "$FILE_LINES" ]
    then
        printf '\n'
        ui_section "$FILE"
        ui_warn "Range starts after end of file ($FILE_LINES lines)."
        return
    fi

    printf '\n'

    if [ -n "$REQUESTED_RANGE" ]
    then
        ui_section "$FILE · lines $RANGE_START-$RANGE_END"
    else
        ui_section "$FILE · lines 1-$FILE_LINES"
    fi

    awk \
        -v start="$RANGE_START" \
        -v end="$RANGE_END" \
        -v dim="$UI_DIM" \
        -v reset="$UI_RESET" \
        '
        NR >= start && NR <= end {
            printf "%s%6d%s │ %s\n", dim, NR, reset, $0
        }
        ' \
        "$FILE"
}

# ============================================================
# ENVIRONMENT
# ============================================================

if ! command -v git >/dev/null 2>&1
then
    printf 'STATUSMAN ERROR: Git was not found in PATH.\n'
    exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1
then
    printf 'STATUSMAN ERROR: not inside a Git repository.\n'
    exit 1
fi

# ============================================================
# TEMPORARY SNAPSHOT FILES
# ============================================================

STATUS_FILE=$(mktemp 2>/dev/null)
AVAILABLE_FILES=$(mktemp 2>/dev/null)
INSPECTION_FILES=$(mktemp 2>/dev/null)
WARNINGS_FILE=$(mktemp 2>/dev/null)

if [ -z "$STATUS_FILE" ] ||
   [ ! -f "$STATUS_FILE" ] ||
   [ -z "$AVAILABLE_FILES" ] ||
   [ ! -f "$AVAILABLE_FILES" ] ||
   [ -z "$INSPECTION_FILES" ] ||
   [ ! -f "$INSPECTION_FILES" ] ||
   [ -z "$WARNINGS_FILE" ] ||
   [ ! -f "$WARNINGS_FILE" ]
then
    printf 'STATUSMAN ERROR: could not create temporary files.\n'

    rm -f \
        "$STATUS_FILE" \
        "$AVAILABLE_FILES" \
        "$INSPECTION_FILES" \
        "$WARNINGS_FILE"

    exit 1
fi

cleanup()
{
    rm -f \
        "$STATUS_FILE" \
        "$AVAILABLE_FILES" \
        "$INSPECTION_FILES" \
        "$WARNINGS_FILE"
}

trap cleanup 0

if ! git status \
    --porcelain=v2 \
    --branch \
    --untracked-files=all \
    > "$STATUS_FILE"
then
    printf 'STATUSMAN ERROR: could not inspect repository status.\n'
    exit 1
fi

git ls-files \
    --cached \
    --others \
    --exclude-standard \
    > "$AVAILABLE_FILES"

# ============================================================
# CLI ARGUMENTS
# ============================================================

REQUESTED_RANGE=""
FILE_ARGUMENT_COUNT=0

if [ "$#" -gt 0 ]
then
    LAST_ARGUMENT=""

    for ARG
    do
        LAST_ARGUMENT=$ARG
    done

    if is_line_range "$LAST_ARGUMENT"
    then
        REQUESTED_RANGE=$LAST_ARGUMENT
        ARGUMENT_COUNT=$#

        if [ "$ARGUMENT_COUNT" -gt 1 ]
        then
            FILE_ARGUMENT_COUNT=$((ARGUMENT_COUNT - 1))
        fi
    else
        FILE_ARGUMENT_COUNT=$#
    fi

    CURRENT_ARGUMENT=0

    for ARG
    do
        CURRENT_ARGUMENT=$((CURRENT_ARGUMENT + 1))

        if [ "$CURRENT_ARGUMENT" -gt "$FILE_ARGUMENT_COUNT" ]
        then
            break
        fi

        resolve_file_argument "$ARG"
    done
fi

# ============================================================
# REPOSITORY METADATA
# ============================================================

REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)

if [ -n "$REMOTE_URL" ]
then
    REPOSITORY_NAME=${REMOTE_URL##*/}
    REPOSITORY_NAME=${REPOSITORY_NAME%.git}
else
    REPOSITORY_NAME=$(basename "$ROOT_DIR")
fi

BRANCH=$(sed -n 's/^# branch.head //p' "$STATUS_FILE")
HEAD_OID=$(sed -n 's/^# branch.oid //p' "$STATUS_FILE")
UPSTREAM=$(sed -n 's/^# branch.upstream //p' "$STATUS_FILE")
AB=$(sed -n 's/^# branch.ab //p' "$STATUS_FILE")

SHORT_OID="unknown"

if [ -n "$HEAD_OID" ]
then
    SHORT_OID=$(printf '%s\n' "$HEAD_OID" | cut -c 1-7)
fi

AHEAD=0
BEHIND=0

if [ -n "$AB" ]
then
    AHEAD=$(
        printf '%s\n' "$AB" |
        awk '{ value = $1; sub(/^\+/, "", value); print value + 0 }'
    )

    BEHIND=$(
        printf '%s\n' "$AB" |
        awk '{ value = $2; sub(/^-/, "", value); print value + 0 }'
    )
fi

STAGED=$(
    awk '
    /^1 / || /^2 / {
        if (substr($2, 1, 1) != ".")
            count++
    }
    END { print count + 0 }
    ' "$STATUS_FILE"
)

UNSTAGED=$(
    awk '
    /^1 / || /^2 / {
        if (substr($2, 2, 1) != ".")
            count++
    }
    END { print count + 0 }
    ' "$STATUS_FILE"
)

UNTRACKED=$(
    awk '
    /^\? / { count++ }
    END { print count + 0 }
    ' "$STATUS_FILE"
)

CONFLICTS=$(
    awk '
    /^u / { count++ }
    END { print count + 0 }
    ' "$STATUS_FILE"
)

STASHES=$(
    git stash list |
    awk 'END { print NR + 0 }'
)

# ============================================================
# SCORE
# ============================================================

DEDUCT_DETACHED=0
DEDUCT_CONFLICTS=0
DEDUCT_BEHIND=0
DEDUCT_UNSTAGED=0
DEDUCT_UNTRACKED=0

if [ -z "$BRANCH" ] ||
   [ "$BRANCH" = "(detached)" ]
then
    DEDUCT_DETACHED=15
fi

if [ "$CONFLICTS" -gt 0 ]
then
    DEDUCT_CONFLICTS=40
fi

if [ "$BEHIND" -gt 0 ]
then
    DEDUCT_BEHIND=15
fi

if [ "$UNSTAGED" -gt 0 ]
then
    DEDUCT_UNSTAGED=10
fi

if [ "$UNTRACKED" -gt 0 ]
then
    DEDUCT_UNTRACKED=5
fi

SCORE=$((100
    - DEDUCT_DETACHED
    - DEDUCT_CONFLICTS
    - DEDUCT_BEHIND
    - DEDUCT_UNSTAGED
    - DEDUCT_UNTRACKED))

if [ "$SCORE" -lt 0 ]
then
    SCORE=0
fi

# ============================================================
# HEADER
# ============================================================

if [ -n "$BRANCH" ] &&
   [ "$BRANCH" != "(detached)" ]
then
    BRANCH_LABEL=$BRANCH
else
    BRANCH_LABEL="detached"
fi

if [ -n "$UPSTREAM" ]
then
    SYNC_LABEL="↑$AHEAD ↓$BEHIND"
else
    SYNC_LABEL="local"
fi

HEADER_META="$BRANCH_LABEL · $SHORT_OID · $SYNC_LABEL · stash $STASHES · SCORE $SCORE"

ui_tool_header \
    "STATUSMAN" \
    "$REPOSITORY_NAME" \
    "$HEADER_META" \
    "$UI_MAGENTA" \
    "$UI_CYAN"

# ============================================================
# WARNINGS
# ============================================================

if [ -s "$WARNINGS_FILE" ]
then
    while IFS= read -r WARNING
    do
        ui_warn "$WARNING"
    done < "$WARNINGS_FILE"

    printf '\n'
fi

# ============================================================
# REPOSITORY STATE
# ============================================================

if [ "$STAGED" -eq 0 ] &&
   [ "$UNSTAGED" -eq 0 ] &&
   [ "$UNTRACKED" -eq 0 ] &&
   [ "$CONFLICTS" -eq 0 ]
then
    ui_ok "Working tree clean."
else
    ui_section "CHANGES"

    if [ "$CONFLICTS" -gt 0 ]
    then
        render_conflicts
    fi

    if [ "$STAGED" -gt 0 ]
    then
        render_name_status staged
    fi

    if [ "$UNSTAGED" -gt 0 ]
    then
        render_name_status unstaged
    fi

    if [ "$UNTRACKED" -gt 0 ]
    then
        render_untracked
    fi

    printf '\n'
    ui_section "DIFF"

    if [ "$STAGED" -gt 0 ]
    then
        render_diff_summary staged
    fi

    if [ "$UNSTAGED" -gt 0 ]
    then
        render_diff_summary unstaged
    fi
fi

# ============================================================
# FILE INSPECTION
# ============================================================

if [ -s "$INSPECTION_FILES" ]
then
    while IFS= read -r FILE
    do
        render_file "$FILE" "$REQUESTED_RANGE"
    done < "$INSPECTION_FILES"
elif [ "$#" -gt 0 ] &&
     [ -n "$REQUESTED_RANGE" ] &&
     [ "$FILE_ARGUMENT_COUNT" -eq 0 ]
then
    printf '\n'
    ui_warn "A line range was provided without a matching file."
fi

# ============================================================
# FOOTER
# ============================================================

if [ "$CONFLICTS" -gt 0 ]
then
    ui_footer_fail "Repository needs attention · SCORE $SCORE"
elif [ "$SCORE" -eq 100 ]
then
    ui_footer_ok "Repository healthy · SCORE $SCORE"
else
    printf '\n'
    ui_divider
    ui_warn "Repository health · SCORE $SCORE"
fi

printf '\n'
exit 0
