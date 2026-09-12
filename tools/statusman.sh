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

status_warn()
{
    printf '%b[WARN]%b %s\n' \
        "$UI_YELLOW" \
        "$UI_RESET" \
        "$1"
}

render_change_stream()
{
    while IFS= read -r line
    do
        case "$line" in
            A*)
                printf '%b  %s%b\n' \
                    "$UI_GREEN" \
                    "$line" \
                    "$UI_RESET"
                ;;

            D*|U*)
                printf '%b  %s%b\n' \
                    "$UI_RED" \
                    "$line" \
                    "$UI_RESET"
                ;;

            M*|R*|C*|T*)
                printf '%b  %s%b\n' \
                    "$UI_YELLOW" \
                    "$line" \
                    "$UI_RESET"
                ;;

            \?\?*)
                printf '%b  %s%b\n' \
                    "$UI_CYAN" \
                    "$line" \
                    "$UI_RESET"
                ;;

            *)
                printf '  %s\n' "$line"
                ;;
        esac
    done
}

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

render_file()
{
    FILE=$1
    REQUESTED_RANGE=$2

    if [ ! -f "$FILE" ]
    then
        status_warn "File does not exist: $FILE"
        return
    fi

    FILE_LINES=$(
        awk 'END {
            print NR + 0
        }' "$FILE"
    )

    RANGE_START=1
    RANGE_END=$FILE_LINES

    if [ -n "$REQUESTED_RANGE" ]
    then
        if ! resolve_range \
            "$REQUESTED_RANGE" \
            "$FILE_LINES"
        then
            status_warn \
                "Invalid line range '$REQUESTED_RANGE' for $FILE"
            return
        fi
    fi

    printf '\n'
    ui_section "FILE :: $FILE"

    printf '  lines ........................ %s\n' "$FILE_LINES"

    if [ -n "$REQUESTED_RANGE" ]
    then
        printf '  requested range .............. %s\n' \
            "$REQUESTED_RANGE"
    else
        printf '  requested range .............. all\n'
    fi

    if [ "$FILE_LINES" -eq 0 ]
    then
        ui_info "File is empty."
        return
    fi

    if [ "$RANGE_START" -gt "$FILE_LINES" ]
    then
        status_warn \
            "Range starts after end of file ($FILE_LINES lines)."
        return
    fi

    printf '  displayed range .............. %s-%s\n' \
        "$RANGE_START" \
        "$RANGE_END"

    printf '\n'

    awk \
        -v start="$RANGE_START" \
        -v end="$RANGE_END" \
        '
        NR >= start && NR <= end {
            printf "%6d | %s\n", NR, $0
        }
        ' \
        "$FILE"
}

add_inspection_file()
{
    FILE=$1

    if grep \
        -Fqx \
        "$FILE" \
        "$INSPECTION_FILES" \
        2>/dev/null
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
        status_warn "No file matches: $ARG"
    fi
}

ui_banner \
    "STATUSMAN :: PROJECT STATUS" \
    "$UI_MAGENTA" \
    "$UI_CYAN"

# ============================================================
# ENVIRONMENT
# ============================================================

if ! command -v git >/dev/null 2>&1
then
    ui_fail "Git was not found in PATH."
    exit 1
fi

if ! git rev-parse \
    --is-inside-work-tree \
    >/dev/null 2>&1
then
    ui_fail "Not inside a Git repository."
    exit 1
fi

# ============================================================
# STATUS SNAPSHOT
# ============================================================

STATUS_FILE=$(mktemp 2>/dev/null)
AVAILABLE_FILES=$(mktemp 2>/dev/null)
INSPECTION_FILES=$(mktemp 2>/dev/null)

if [ -z "$STATUS_FILE" ] ||
   [ ! -f "$STATUS_FILE" ] ||
   [ -z "$AVAILABLE_FILES" ] ||
   [ ! -f "$AVAILABLE_FILES" ] ||
   [ -z "$INSPECTION_FILES" ] ||
   [ ! -f "$INSPECTION_FILES" ]
then
    ui_fail "Could not create temporary Statusman files."

    rm -f \
        "$STATUS_FILE" \
        "$AVAILABLE_FILES" \
        "$INSPECTION_FILES"

    exit 1
fi

cleanup()
{
    rm -f \
        "$STATUS_FILE" \
        "$AVAILABLE_FILES" \
        "$INSPECTION_FILES"
}

trap cleanup 0

if ! git status \
    --porcelain=v2 \
    --branch \
    --untracked-files=all \
    > "$STATUS_FILE"
then
    ui_fail "Could not inspect repository status."
    exit 1
fi

git ls-files \
    --cached \
    --others \
    --exclude-standard \
    > "$AVAILABLE_FILES"

    REQUESTED_RANGE=""

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
        else
            FILE_ARGUMENT_COUNT=0
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
# REPOSITORY NAME
# ============================================================

REMOTE_URL=$(
    git remote get-url origin 2>/dev/null || true
)

if [ -n "$REMOTE_URL" ]
then
    REPOSITORY_NAME=${REMOTE_URL##*/}
    REPOSITORY_NAME=${REPOSITORY_NAME%.git}
else
    REPOSITORY_NAME=$(
        basename "$ROOT_DIR"
    )
fi

# ============================================================
# BRANCH METADATA
# ============================================================

BRANCH=$(
    sed -n \
        's/^# branch.head //p' \
        "$STATUS_FILE"
)

HEAD_OID=$(
    sed -n \
        's/^# branch.oid //p' \
        "$STATUS_FILE"
)

UPSTREAM=$(
    sed -n \
        's/^# branch.upstream //p' \
        "$STATUS_FILE"
)

AB=$(
    sed -n \
        's/^# branch.ab //p' \
        "$STATUS_FILE"
)

AHEAD=0
BEHIND=0

if [ -n "$AB" ]
then
    AHEAD=$(
        printf '%s\n' "$AB" |
        awk '{
            value = $1
            sub(/^\+/, "", value)
            print value + 0
        }'
    )

    BEHIND=$(
        printf '%s\n' "$AB" |
        awk '{
            value = $2
            sub(/^-/, "", value)
            print value + 0
        }'
    )
fi

# ============================================================
# WORKTREE COUNTS
# ============================================================

STAGED=$(
    awk '
    /^1 / || /^2 / {
        if (substr($2, 1, 1) != ".")
            count++
    }

    END {
        print count + 0
    }
    ' "$STATUS_FILE"
)

UNSTAGED=$(
    awk '
    /^1 / || /^2 / {
        if (substr($2, 2, 1) != ".")
            count++
    }

    END {
        print count + 0
    }
    ' "$STATUS_FILE"
)

UNTRACKED=$(
    awk '
    /^\? / {
        count++
    }

    END {
        print count + 0
    }
    ' "$STATUS_FILE"
)

CONFLICTS=$(
    awk '
    /^u / {
        count++
    }

    END {
        print count + 0
    }
    ' "$STATUS_FILE"
)

STASHES=$(
    git stash list |
    awk 'END {
        print NR + 0
    }'
)

# ============================================================
# REPOSITORY DASHBOARD
# ============================================================

printf '\n'
ui_section "REPOSITORY"

ui_info "Repository: $REPOSITORY_NAME"

if [ -n "$BRANCH" ] &&
   [ "$BRANCH" != "(detached)" ]
then
    ui_info "Branch: $BRANCH"
else
    status_warn "Detached HEAD."
fi

if [ -n "$HEAD_OID" ]
then
    SHORT_OID=$(
        printf '%s\n' "$HEAD_OID" |
        cut -c 1-7
    )

    ui_info "HEAD: $SHORT_OID"
fi

if [ -n "$UPSTREAM" ]
then
    ui_info "Upstream: $UPSTREAM"

    printf '  ahead ........................ %s\n' "$AHEAD"
    printf '  behind ....................... %s\n' "$BEHIND"

    if [ "$AHEAD" -eq 0 ] &&
       [ "$BEHIND" -eq 0 ]
    then
        ui_ok "Branch synchronized with known upstream state."
    elif [ "$BEHIND" -gt 0 ]
    then
        status_warn "Branch is behind upstream."
    elif [ "$AHEAD" -gt 0 ]
    then
        ui_info "Branch contains local commits not in upstream."
    fi
else
    ui_info "Upstream: none"
    ui_info "Ahead/behind: not available."
fi

printf '  stashes ...................... %s\n' "$STASHES"

# ============================================================
# WORKTREE DASHBOARD
# ============================================================

printf '\n'
ui_section "WORKTREE"

printf '  staged ....................... %s\n' "$STAGED"
printf '  unstaged ..................... %s\n' "$UNSTAGED"
printf '  untracked .................... %s\n' "$UNTRACKED"
printf '  conflicts .................... %s\n' "$CONFLICTS"

if [ "$STAGED" -eq 0 ] &&
   [ "$UNSTAGED" -eq 0 ] &&
   [ "$UNTRACKED" -eq 0 ] &&
   [ "$CONFLICTS" -eq 0 ]
then
    printf '\n'
    ui_ok "Working tree clean."
else
    printf '\n'

    if [ "$CONFLICTS" -gt 0 ]
    then
        status_warn "Repository contains merge conflicts."
    else
        ui_info "Repository contains local changes."
    fi
fi

# ============================================================
# CONFLICTS
# ============================================================

if [ "$CONFLICTS" -gt 0 ]
then
    printf '\n'
    ui_section "CONFLICTS"

    git diff \
        --name-only \
        --diff-filter=U |
    sed 's/^/U\t/' |
    render_change_stream
fi

# ============================================================
# STAGED DIFF
# ============================================================

if [ "$STAGED" -gt 0 ]
then
    printf '\n'
    ui_section "STAGED DIFF"

    printf '%bCHECK%b\n' \
        "${UI_BOLD}${UI_WHITE}" \
        "$UI_RESET"

    if git diff --cached --check
    then
        ui_ok "Staged diff whitespace clean."
    else
        status_warn "Staged diff contains whitespace errors."
    fi

    printf '\n'
    printf '%bSTAT%b\n' \
        "${UI_BOLD}${UI_WHITE}" \
        "$UI_RESET"

    git diff \
        --cached \
        --stat

    printf '\n'
    printf '%bNAME STATUS%b\n' \
        "${UI_BOLD}${UI_WHITE}" \
        "$UI_RESET"

    git diff \
        --cached \
        --name-status |
    render_change_stream
fi

# ============================================================
# UNSTAGED DIFF
# ============================================================

if [ "$UNSTAGED" -gt 0 ]
then
    printf '\n'
    ui_section "UNSTAGED DIFF"

    printf '%bCHECK%b\n' \
        "${UI_BOLD}${UI_WHITE}" \
        "$UI_RESET"

    if git diff --check
    then
        ui_ok "Unstaged diff whitespace clean."
    else
        status_warn "Unstaged diff contains whitespace errors."
    fi

    printf '\n'
    printf '%bSTAT%b\n' \
        "${UI_BOLD}${UI_WHITE}" \
        "$UI_RESET"

    git diff --stat

    printf '\n'
    printf '%bNAME STATUS%b\n' \
        "${UI_BOLD}${UI_WHITE}" \
        "$UI_RESET"

    git diff \
        --name-status |
    render_change_stream
fi

# ============================================================
# UNTRACKED FILES
# ============================================================

if [ "$UNTRACKED" -gt 0 ]
then
    printf '\n'
    ui_section "UNTRACKED"

    git ls-files \
        --others \
        --exclude-standard |
    sed 's/^/??\t/' |
    render_change_stream
fi

# ============================================================
# FILE INSPECTION
# ============================================================

if [ -s "$INSPECTION_FILES" ]
then
    while IFS= read -r FILE
    do
        render_file \
            "$FILE" \
            "$REQUESTED_RANGE"
    done < "$INSPECTION_FILES"
elif [ "$#" -gt 0 ] &&
     [ -n "$REQUESTED_RANGE" ]
then
    status_warn "A line range was provided without a matching file."
fi

# ============================================================
# SCORE
# ============================================================

SCORE=100

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

printf '\n'
ui_section "SCORE"

printf '  baseline ..................... 100\n'

if [ "$DEDUCT_DETACHED" -gt 0 ]
then
    printf '  detached HEAD ................ -%s\n' \
        "$DEDUCT_DETACHED"
fi

if [ "$DEDUCT_CONFLICTS" -gt 0 ]
then
    printf '  conflicts .................... -%s\n' \
        "$DEDUCT_CONFLICTS"
fi

if [ "$DEDUCT_BEHIND" -gt 0 ]
then
    printf '  behind upstream .............. -%s\n' \
        "$DEDUCT_BEHIND"
fi

if [ "$DEDUCT_UNSTAGED" -gt 0 ]
then
    printf '  unstaged changes ............. -%s\n' \
        "$DEDUCT_UNSTAGED"
fi

if [ "$DEDUCT_UNTRACKED" -gt 0 ]
then
    printf '  untracked files .............. -%s\n' \
        "$DEDUCT_UNTRACKED"
fi

printf '  ------------------------------------------\n'

if [ "$SCORE" -eq 100 ]
then
    ui_ok "Repository health: $SCORE / 100"
elif [ "$SCORE" -ge 80 ]
then
    ui_info "Repository health: $SCORE / 100"
else
    status_warn "Repository health: $SCORE / 100"
fi

printf '\n'

ui_banner \
    "STATUSMAN :: OBSERVATION COMPLETE" \
    "$UI_MAGENTA" \
    "$UI_CYAN"

exit 0
