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

if [ -z "$STATUS_FILE" ] ||
   [ ! -f "$STATUS_FILE" ]
then
    ui_fail "Could not create temporary status file."
    exit 1
fi

cleanup()
{
    rm -f "$STATUS_FILE"
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
