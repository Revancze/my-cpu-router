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


build_diff_markers()
{
    FILE=$1
    MODE=$2
    MARKER_FILE=$3
    REMOVAL_FILE=$4

    : > "$MARKER_FILE"
    : > "$REMOVAL_FILE"

    if [ "$MODE" = "untracked" ]
    then
        awk '{ print NR "\t+" }' "$FILE" > "$MARKER_FILE"
        return
    fi

    if [ "$MODE" = "staged" ]
    then
        DIFF_COMMAND="git diff --cached --unified=0 --no-color --"
    else
        DIFF_COMMAND="git diff --unified=0 --no-color --"
    fi

    $DIFF_COMMAND "$FILE" |
    awk \
        -v markers="$MARKER_FILE" \
        -v removals="$REMOVAL_FILE" \
        '
        /^@@ / {
            old_spec = $2
            new_spec = $3

            sub(/^-/, "", old_spec)
            sub(/^\+/, "", new_spec)

            old_parts_count = split(old_spec, old_parts, ",")
            new_parts_count = split(new_spec, new_parts, ",")

            old_count = (old_parts_count > 1) ? old_parts[2] + 0 : 1
            new_start = new_parts[1] + 0
            new_count = (new_parts_count > 1) ? new_parts[2] + 0 : 1

            if (old_count == 0) {
                for (i = 0; i < new_count; ++i)
                    print (new_start + i) "\t+" >> markers

                next
            }

            if (new_count == 0) {
                print old_count >> removals
                next
            }

            common = (old_count < new_count) ? old_count : new_count

            for (i = 0; i < common; ++i)
                print (new_start + i) "\t~" >> markers

            for (i = common; i < new_count; ++i)
                print (new_start + i) "\t+" >> markers

            if (old_count > new_count)
                print (old_count - new_count) >> removals
        }
        '
}

render_marker_summary()
{
    ADDED_COUNT=$1
    MODIFIED_COUNT=$2
    REMOVED_COUNT=$3

    if [ "$ADDED_COUNT" -eq 0 ] &&
       [ "$MODIFIED_COUNT" -eq 0 ] &&
       [ "$REMOVED_COUNT" -eq 0 ]
    then
        return
    fi

    printf '\n  '
    FIRST_SUMMARY=1

    if [ "$ADDED_COUNT" -gt 0 ]
    then
        printf '%b+%s added%b' \
            "$UI_GREEN" \
            "$ADDED_COUNT" \
            "$UI_RESET"
        FIRST_SUMMARY=0
    fi

    if [ "$MODIFIED_COUNT" -gt 0 ]
    then
        if [ "$FIRST_SUMMARY" -eq 0 ]
        then
            printf ' · '
        fi

        printf '%b~%s changed%b' \
            "$UI_YELLOW" \
            "$MODIFIED_COUNT" \
            "$UI_RESET"
        FIRST_SUMMARY=0
    fi

    if [ "$REMOVED_COUNT" -gt 0 ]
    then
        if [ "$FIRST_SUMMARY" -eq 0 ]
        then
            printf ' · '
        fi

        printf '%b-%s removed%b' \
            "$UI_RED" \
            "$REMOVED_COUNT" \
            "$UI_RESET"
    fi

    printf '\n'
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

    FILE_STAGED=0
    FILE_UNSTAGED=0
    FILE_UNTRACKED=0

    if ! git ls-files --error-unmatch -- "$FILE" >/dev/null 2>&1
    then
        FILE_UNTRACKED=1
    else
        if ! git diff --cached --quiet -- "$FILE"
        then
            FILE_STAGED=1
        fi

        if ! git diff --quiet -- "$FILE"
        then
            FILE_UNSTAGED=1
        fi
    fi

    MARKER_MODE="clean"
    FILE_STATE="clean"

    if [ "$FILE_UNTRACKED" -eq 1 ]
    then
        MARKER_MODE="untracked"
        FILE_STATE="untracked"
    elif [ "$FILE_UNSTAGED" -eq 1 ] &&
         [ "$FILE_STAGED" -eq 1 ]
    then
        MARKER_MODE="unstaged"
        FILE_STATE="staged + unstaged"
    elif [ "$FILE_UNSTAGED" -eq 1 ]
    then
        MARKER_MODE="unstaged"
        FILE_STATE="unstaged"
    elif [ "$FILE_STAGED" -eq 1 ]
    then
        MARKER_MODE="staged"
        FILE_STATE="staged"
    fi

    if [ "$FILE_LINES" -eq 0 ]
    then
        printf '\n'
        ui_section "$FILE · $FILE_STATE"
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

    MARKER_FILE=$(mktemp)
    REMOVAL_FILE=$(mktemp)

    if [ -z "$MARKER_FILE" ] ||
       [ ! -f "$MARKER_FILE" ] ||
       [ -z "$REMOVAL_FILE" ] ||
       [ ! -f "$REMOVAL_FILE" ]
    then
        rm -f "$MARKER_FILE" "$REMOVAL_FILE"
        ui_warn "Could not create diff marker files for $FILE"
        return
    fi

    if [ "$MARKER_MODE" != "clean" ]
    then
        build_diff_markers \
            "$FILE" \
            "$MARKER_MODE" \
            "$MARKER_FILE" \
            "$REMOVAL_FILE"
    else
        : > "$MARKER_FILE"
        : > "$REMOVAL_FILE"
    fi

    ADDED_COUNT=$(
        awk -F '\t' '$2 == "+" { count++ } END { print count + 0 }' \
            "$MARKER_FILE"
    )

    MODIFIED_COUNT=$(
        awk -F '\t' '$2 == "~" { count++ } END { print count + 0 }' \
            "$MARKER_FILE"
    )

    REMOVED_COUNT=$(
        awk '{ total += $1 } END { print total + 0 }' \
            "$REMOVAL_FILE"
    )

    printf '\n'

    if [ -n "$REQUESTED_RANGE" ]
    then
        ui_section "$FILE · lines $RANGE_START-$RANGE_END · $FILE_STATE"
    else
        ui_section "$FILE · lines 1-$FILE_LINES · $FILE_STATE"
    fi

    if [ "$FILE_STAGED" -eq 1 ] &&
       [ "$FILE_UNSTAGED" -eq 1 ]
    then
        ui_muted "line markers show unstaged working-tree changes"
        printf '\n'
    fi

    awk \
        -F '\t' \
        -v start="$RANGE_START" \
        -v end="$RANGE_END" \
        -v dim="$UI_DIM" \
        -v green="$UI_GREEN" \
        -v yellow="$UI_YELLOW" \
        -v reset="$UI_RESET" \
        '
        NR == FNR {
            marker[$1] = $2
            next
        }

        FNR >= start && FNR <= end {
            kind = marker[FNR]
            prefix = " "
            color = ""

            if (kind == "+") {
                prefix = "+"
                color = green
            } else if (kind == "~") {
                prefix = "~"
                color = yellow
            }

            printf "%s%s%s %s%6d%s │ %s\n", \
                color, prefix, reset, dim, FNR, reset, $0
        }
        ' \
        "$MARKER_FILE" \
        "$FILE"

    render_marker_summary \
        "$ADDED_COUNT" \
        "$MODIFIED_COUNT" \
        "$REMOVED_COUNT"

    if [ "$REMOVED_COUNT" -gt 0 ]
    then
        ui_muted "removed lines are summarized because they no longer exist in the current file"
    fi

    rm -f "$MARKER_FILE" "$REMOVAL_FILE"
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

    if [ "$STAGED" -gt 0 ] ||
       [ "$UNSTAGED" -gt 0 ]
    then
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
