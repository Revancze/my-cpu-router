#!/usr/bin/env bash

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

resolve_compare_ref()
{
    REF_ARGUMENT=$1
    RESOLVED_COMPARE_REF=""
    RESOLVED_COMPARE_LABEL=""

    if [ "$REF_ARGUMENT" = "upstream" ]
    then
        if git rev-parse --verify --quiet '@{upstream}^{commit}' >/dev/null 2>&1
        then
            RESOLVED_COMPARE_REF='@{upstream}'
            RESOLVED_COMPARE_LABEL='upstream'
            return 0
        fi

        return 1
    fi

    if git rev-parse --verify --quiet "${REF_ARGUMENT}^{commit}" >/dev/null 2>&1
    then
        RESOLVED_COMPARE_REF=$REF_ARGUMENT
        RESOLVED_COMPARE_LABEL=$REF_ARGUMENT
        return 0
    fi

    if git rev-parse --verify --quiet "refs/remotes/origin/${REF_ARGUMENT}^{commit}" >/dev/null 2>&1
    then
        RESOLVED_COMPARE_REF="origin/$REF_ARGUMENT"
        RESOLVED_COMPARE_LABEL="origin/$REF_ARGUMENT"
        queue_warning "Ref '$REF_ARGUMENT' not found locally; using origin/$REF_ARGUMENT."
        return 0
    fi

    return 1
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

# ============================================================
# LAYOUT HELPERS
# ============================================================

FILE_COLUMN_WIDTH=${STATUSMAN_FILE_WIDTH:-28}
NUMBER_COLUMN_WIDTH=6

middle_truncate()
{
    TEXT=$1
    WIDTH=$2

    awk -v text="$TEXT" -v width="$WIDTH" '
        BEGIN {
            if (width < 5) {
                print substr(text, 1, width)
                exit
            }

            if (length(text) <= width) {
                print text
                exit
            }

            left = int((width - 3) / 2)
            right = width - 3 - left

            print substr(text, 1, left) "..." substr(text, length(text) - right + 1)
        }
    '
}

render_state_cell()
{
    STATE=$1

    # The cell is always exactly two terminal columns wide. ANSI escapes
    # are applied only while rendering and therefore never participate in
    # width calculations.
    case "$STATE" in
        clean)
            printf '%b✔%b ' "$UI_GREEN" "$UI_RESET"
            ;;
        committed)
            printf '%b◆%b ' "$UI_MAGENTA" "$UI_RESET"
            ;;
        staged)
            printf '%b✚%b ' "$UI_CYAN" "$UI_RESET"
            ;;
        unstaged)
            printf ' %b✎%b' "$UI_YELLOW" "$UI_RESET"
            ;;
        both)
            printf '%b✚%b%b✎%b' "$UI_CYAN" "$UI_RESET" "$UI_YELLOW" "$UI_RESET"
            ;;
        untracked)
            printf '%b?%b ' "$UI_CYAN" "$UI_RESET"
            ;;
        conflict)
            printf '%b✖%b ' "$UI_RED" "$UI_RESET"
            ;;
        renamed)
            printf '%b»%b ' "$UI_MAGENTA" "$UI_RESET"
            ;;
        deleted)
            printf '%b-%b ' "$UI_RED" "$UI_RESET"
            ;;
        ignored)
            printf '%b◌%b ' "$UI_DIM" "$UI_RESET"
            ;;
        *)
            printf '  '
            ;;
    esac
}

render_changes_header()
{
    printf '  %-2s %-*s %*s %*s\n' \
        'ST' \
        "$FILE_COLUMN_WIDTH" \
        'FILE' \
        "$NUMBER_COLUMN_WIDTH" \
        '+ADD' \
        "$NUMBER_COLUMN_WIDTH" \
        '-DEL'
}

render_change_row()
{
    STATE=$1
    DISPLAY_PATH=$2
    MODE=$3
    PATH_A=$4
    PATH_B=${5:-}

    SHORT_PATH=$(middle_truncate "$DISPLAY_PATH" "$FILE_COLUMN_WIDTH")

    if [ "$MODE" = "untracked" ]
    then
        if [ -f "$PATH_A" ]
        then
            ADD_COUNT=$(awk 'END { print NR + 0 }' "$PATH_A")
        else
            ADD_COUNT=0
        fi
        DEL_COUNT=0
    else
        if [ "$MODE" = "staged" ]
        then
            if [ -n "$PATH_B" ]
            then
                NUMSTAT=$(git diff --cached --numstat -- "$PATH_A" "$PATH_B")
            else
                NUMSTAT=$(git diff --cached --numstat -- "$PATH_A")
            fi
        else
            if [ -n "$PATH_B" ]
            then
                NUMSTAT=$(git diff --numstat -- "$PATH_A" "$PATH_B")
            else
                NUMSTAT=$(git diff --numstat -- "$PATH_A")
            fi
        fi

        COUNTS=$(printf '%s\n' "$NUMSTAT" | awk -F '\t' '
            NF >= 2 {
                if ($1 == "-" || $2 == "-") {
                    binary = 1
                    next
                }

                add += $1
                del += $2
            }

            END {
                if (binary)
                    print "? ?"
                else
                    print add + 0, del + 0
            }
        ')

        set -- $COUNTS
        ADD_COUNT=${1:-0}
        DEL_COUNT=${2:-0}
    fi

    if [ "$ADD_COUNT" = "?" ]
    then
        ADD_TEXT="+?"
    else
        ADD_TEXT="+$ADD_COUNT"
    fi

    if [ "$DEL_COUNT" = "?" ]
    then
        DEL_TEXT="-?"
    else
        DEL_TEXT="-$DEL_COUNT"
    fi

    ADD_PAD=$(printf "%${NUMBER_COLUMN_WIDTH}s" "$ADD_TEXT")
    DEL_PAD=$(printf "%${NUMBER_COLUMN_WIDTH}s" "$DEL_TEXT")

    printf '  '
    render_state_cell "$STATE"
    printf ' %-*s ' "$FILE_COLUMN_WIDTH" "$SHORT_PATH"
    printf '%b%s%b ' "$UI_GREEN" "$ADD_PAD" "$UI_RESET"
    printf '%b%s%b\n' "$UI_RED" "$DEL_PAD" "$UI_RESET"
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
        STATE=$MODE
        DISPLAY_PATH=$FILE
        QUERY_A=$FILE
        QUERY_B=""

        case "$KIND" in
            D)
                STATE="deleted"
                ;;
            R*|C*)
                STATE="renamed"
                if [ -n "$REST" ]
                then
                    DISPLAY_PATH="$FILE → $REST"
                    QUERY_B=$REST
                fi
                ;;
            U*)
                # Conflicts are rendered once by render_conflicts().
                continue
                ;;
        esac

        render_change_row \
            "$STATE" \
            "$DISPLAY_PATH" \
            "$MODE" \
            "$QUERY_A" \
            "$QUERY_B"
    done
}
render_untracked()
{
    git ls-files --others --exclude-standard |
    while IFS= read -r FILE
    do
        render_change_row "untracked" "$FILE" "untracked" "$FILE"
    done
}

render_conflicts()
{
    git diff --name-only --diff-filter=U |
    while IFS= read -r FILE
    do
        render_change_row "conflict" "$FILE" "unstaged" "$FILE"
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


parse_diff_markers()
{
    MARKER_FILE=$1
    REMOVAL_FILE=$2

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
                # Deleted lines have no current line number. Anchor the
                # deletion at the nearest following worktree line.
                removal_anchor = new_start + 1
                print removal_anchor "\t" old_count >> removals
                next
            }

            common = (old_count < new_count) ? old_count : new_count

            for (i = 0; i < common; ++i)
                print (new_start + i) "\t~" >> markers

            for (i = common; i < new_count; ++i)
                print (new_start + i) "\t+" >> markers

            if (old_count > new_count) {
                removal_anchor = new_start + new_count
                print removal_anchor "\t" (old_count - new_count) >> removals
            }
        }
        '
}

build_diff_markers()
{
    FILE=$1
    MODE=$2
    MARKER_FILE=$3
    REMOVAL_FILE=$4
    COMPARE_REF=${5:-}

    : > "$MARKER_FILE"
    : > "$REMOVAL_FILE"

    if [ "$MODE" = "untracked" ]
    then
        awk '{ print NR "\t+" }' "$FILE" > "$MARKER_FILE"
        return
    fi

    if [ "$MODE" = "staged" ]
    then
        git diff --cached --unified=0 --no-color -- "$FILE" |
        parse_diff_markers "$MARKER_FILE" "$REMOVAL_FILE"
        return
    fi

    if [ "$MODE" = "unstaged" ]
    then
        git diff --unified=0 --no-color -- "$FILE" |
        parse_diff_markers "$MARKER_FILE" "$REMOVAL_FILE"
        return
    fi

    if [ "$MODE" = "ref" ]
    then
        if ! git ls-files --error-unmatch -- "$FILE" >/dev/null 2>&1
        then
            if ! git cat-file -e "$COMPARE_REF:$FILE" 2>/dev/null
            then
                awk '{ print NR "\t+" }' "$FILE" > "$MARKER_FILE"
                return
            fi

            BASE_FILE=$(mktemp 2>/dev/null)

            if [ -z "$BASE_FILE" ] ||
               [ ! -f "$BASE_FILE" ]
            then
                return
            fi

            if git show "$COMPARE_REF:$FILE" > "$BASE_FILE" 2>/dev/null
            then
                git diff \
                    --no-index \
                    --unified=0 \
                    --no-color \
                    -- "$BASE_FILE" "$FILE" 2>/dev/null |
                parse_diff_markers "$MARKER_FILE" "$REMOVAL_FILE"
            fi

            rm -f "$BASE_FILE"
            return
        fi

        git diff "$COMPARE_REF" --unified=0 --no-color -- "$FILE" |
        parse_diff_markers "$MARKER_FILE" "$REMOVAL_FILE"
    fi
}

render_compare_file_stat()
{
    FILE=$1
    COMPARE_REF=$2

    if [ ! -f "$FILE" ]
    then
        FILE_STAT=$(git diff --shortstat "$COMPARE_REF" -- "$FILE" | sed 's/^[[:space:]]*//')

        if [ -n "$FILE_STAT" ]
        then
            FILE_STAT=$(printf '%s\n' "$FILE_STAT" | sed 's/^1 file changed, //; s/^1 file changed$/changed/')
            ui_muted "$FILE · $FILE_STAT"
        else
            ui_warn "$FILE · file is not present in the worktree"
        fi

        return
    fi

    if ! git ls-files --error-unmatch -- "$FILE" >/dev/null 2>&1
    then
        if ! git cat-file -e "$COMPARE_REF:$FILE" 2>/dev/null
        then
            FILE_LINES=$(awk 'END { print NR + 0 }' "$FILE")
            ui_muted "$FILE · new file · $FILE_LINES lines"
            return
        fi

        BASE_FILE=$(mktemp 2>/dev/null)

        if [ -z "$BASE_FILE" ] ||
           [ ! -f "$BASE_FILE" ]
        then
            ui_warn "$FILE · could not calculate comparison statistics"
            return
        fi

        FILE_STAT=""

        if git show "$COMPARE_REF:$FILE" > "$BASE_FILE" 2>/dev/null
        then
            FILE_STAT=$(
                git diff --no-index --shortstat -- "$BASE_FILE" "$FILE" 2>/dev/null |
                sed 's/^[[:space:]]*//'
            )
        fi

        rm -f "$BASE_FILE"
    else
        FILE_STAT=$(
            git diff --shortstat "$COMPARE_REF" -- "$FILE" |
            sed 's/^[[:space:]]*//'
        )
    fi

    if [ -n "$FILE_STAT" ]
    then
        FILE_STAT=$(printf '%s\n' "$FILE_STAT" | sed 's/^1 file changed, //; s/^1 file changed$/changed/')
        ui_muted "$FILE · $FILE_STAT"
    else
        ui_ok "$FILE · no differences"
    fi
}

build_unstaged_hunk_map()
{
    FILE=$1
    MAP_FILE=$2

    : > "$MAP_FILE"

    git diff --unified=0 --no-color -- "$FILE" |
    awk -F ' ' '
        /^@@ / {
            old_spec = $2
            new_spec = $3

            sub(/^-/, "", old_spec)
            sub(/^\+/, "", new_spec)

            old_parts_count = split(old_spec, old_parts, ",")
            new_parts_count = split(new_spec, new_parts, ",")

            old_start = old_parts[1] + 0
            old_count = (old_parts_count > 1) ? old_parts[2] + 0 : 1
            new_start = new_parts[1] + 0
            new_count = (new_parts_count > 1) ? new_parts[2] + 0 : 1

            print old_start "\t" old_count "\t" new_start "\t" new_count
        }
    ' > "$MAP_FILE"
}

map_index_markers_to_worktree()
{
    MAP_FILE=$1
    INDEX_MARKERS=$2
    WORKTREE_MARKERS=$3

    : > "$WORKTREE_MARKERS"

    awk -F '\t' '
        FILENAME == ARGV[1] {
            ++hunks
            old_start[hunks] = $1 + 0
            old_count[hunks] = $2 + 0
            new_start[hunks] = $3 + 0
            new_count[hunks] = $4 + 0
            next
        }

        FILENAME == ARGV[2] {
            line = $1 + 0
            marker = $2
            mapped = line
            delta = 0

            for (i = 1; i <= hunks; ++i) {
                os = old_start[i]
                oc = old_count[i]
                ns = new_start[i]
                nc = new_count[i]

                # Pure insertion in the worktree happens after old line os.
                if (oc == 0) {
                    if (line > os)
                        delta += nc

                    mapped = line + delta
                    continue
                }

                oe = os + oc - 1

                if (line < os)
                    break

                if (line <= oe) {
                    rel = line - os

                    if (nc == 0) {
                        mapped = ns
                        if (mapped < 1)
                            mapped = 1
                    } else if (rel < nc) {
                        mapped = ns + rel
                    } else {
                        mapped = ns + nc - 1
                    }

                    break
                }

                delta += nc - oc
                mapped = line + delta
            }

            if (mapped >= 1)
                print mapped "\t" marker
        }
    ' "$MAP_FILE" "$INDEX_MARKERS" > "$WORKTREE_MARKERS"
}

build_lifecycle_states()
{
    FILE=$1
    REF_MARKER_FILE=$2
    STATE_FILE=$3
    FILE_LINES=$4

    : > "$STATE_FILE"

    if ! git ls-files --error-unmatch -- "$FILE" >/dev/null 2>&1
    then
        awk -v lines="$FILE_LINES" 'BEGIN { for (i = 1; i <= lines; ++i) print i "\tuntracked" }' \
            > "$STATE_FILE"
        return
    fi

    if [ -n "$(git diff --name-only --diff-filter=U -- "$FILE")" ]
    then
        awk -v lines="$FILE_LINES" 'BEGIN { for (i = 1; i <= lines; ++i) print i "\tconflict" }' \
            > "$STATE_FILE"
        return
    fi

    LIFE_STAGED_INDEX=$(mktemp 2>/dev/null)
    LIFE_STAGED_REMOVALS=$(mktemp 2>/dev/null)
    LIFE_UNSTAGED=$(mktemp 2>/dev/null)
    LIFE_UNSTAGED_REMOVALS=$(mktemp 2>/dev/null)
    LIFE_MAP=$(mktemp 2>/dev/null)
    LIFE_STAGED_WORKTREE=$(mktemp 2>/dev/null)

    if [ -z "$LIFE_STAGED_INDEX" ] || [ ! -f "$LIFE_STAGED_INDEX" ] ||
       [ -z "$LIFE_STAGED_REMOVALS" ] || [ ! -f "$LIFE_STAGED_REMOVALS" ] ||
       [ -z "$LIFE_UNSTAGED" ] || [ ! -f "$LIFE_UNSTAGED" ] ||
       [ -z "$LIFE_UNSTAGED_REMOVALS" ] || [ ! -f "$LIFE_UNSTAGED_REMOVALS" ] ||
       [ -z "$LIFE_MAP" ] || [ ! -f "$LIFE_MAP" ] ||
       [ -z "$LIFE_STAGED_WORKTREE" ] || [ ! -f "$LIFE_STAGED_WORKTREE" ]
    then
        rm -f \
            "$LIFE_STAGED_INDEX" \
            "$LIFE_STAGED_REMOVALS" \
            "$LIFE_UNSTAGED" \
            "$LIFE_UNSTAGED_REMOVALS" \
            "$LIFE_MAP" \
            "$LIFE_STAGED_WORKTREE"
        return
    fi

    build_diff_markers \
        "$FILE" \
        staged \
        "$LIFE_STAGED_INDEX" \
        "$LIFE_STAGED_REMOVALS"

    build_diff_markers \
        "$FILE" \
        unstaged \
        "$LIFE_UNSTAGED" \
        "$LIFE_UNSTAGED_REMOVALS"

    build_unstaged_hunk_map "$FILE" "$LIFE_MAP"

    map_index_markers_to_worktree \
        "$LIFE_MAP" \
        "$LIFE_STAGED_INDEX" \
        "$LIFE_STAGED_WORKTREE"

    awk -F '\t' -v lines="$FILE_LINES" '
        FILENAME == ARGV[1] {
            ref_changed[$1] = 1
            next
        }

        FILENAME == ARGV[2] {
            staged[$1] = 1
            next
        }

        FILENAME == ARGV[3] {
            unstaged[$1] = 1
            next
        }

        END {
            for (i = 1; i <= lines; ++i) {
                if (staged[i] && unstaged[i])
                    state = "both"
                else if (staged[i])
                    state = "staged"
                else if (unstaged[i])
                    state = "unstaged"
                else if (ref_changed[i])
                    state = "committed"
                else
                    state = "clean"

                print i "\t" state
            }
        }
    ' \
        "$REF_MARKER_FILE" \
        "$LIFE_STAGED_WORKTREE" \
        "$LIFE_UNSTAGED" \
        > "$STATE_FILE"

    rm -f \
        "$LIFE_STAGED_INDEX" \
        "$LIFE_STAGED_REMOVALS" \
        "$LIFE_UNSTAGED" \
        "$LIFE_UNSTAGED_REMOVALS" \
        "$LIFE_MAP" \
        "$LIFE_STAGED_WORKTREE"
}

build_hunk_selection()
{
    MARKER_FILE=$1
    REMOVAL_FILE=$2
    FILE_LINES=$3
    SHOW_FILE=$4

    : > "$SHOW_FILE"

    awk -F '\t' -v max="$FILE_LINES" '
        FILENAME == ARGV[1] {
            center = $1 + 0

            for (i = center - 2; i <= center + 2; ++i)
                if (i >= 1 && i <= max)
                    show[i] = 1

            next
        }

        FILENAME == ARGV[2] {
            center = $1 + 0

            if (center < 1)
                center = 1
            if (center > max)
                center = max

            for (i = center - 2; i <= center + 2; ++i)
                if (i >= 1 && i <= max)
                    show[i] = 1
        }

        END {
            for (i = 1; i <= max; ++i)
                if (show[i])
                    print i
        }
    ' "$MARKER_FILE" "$REMOVAL_FILE" > "$SHOW_FILE"
}

render_ref_summary()
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

    printf '\nREF    '
    FIRST_SUMMARY=1

    if [ "$ADDED_COUNT" -gt 0 ]
    then
        printf '%b+%s added%b' "$UI_GREEN" "$ADDED_COUNT" "$UI_RESET"
        FIRST_SUMMARY=0
    fi

    if [ "$MODIFIED_COUNT" -gt 0 ]
    then
        if [ "$FIRST_SUMMARY" -eq 0 ]
        then
            printf ' · '
        fi

        printf '%b~%s changed%b' "$UI_YELLOW" "$MODIFIED_COUNT" "$UI_RESET"
        FIRST_SUMMARY=0
    fi

    if [ "$REMOVED_COUNT" -gt 0 ]
    then
        if [ "$FIRST_SUMMARY" -eq 0 ]
        then
            printf ' · '
        fi

        printf '%b-%s removed%b' "$UI_RED" "$REMOVED_COUNT" "$UI_RESET"
    fi

    printf '\n'
}

render_lifecycle_summary()
{
    STATE_FILE=$1
    RANGE_START=$2
    RANGE_END=$3
    SHOW_FILE=${4:-}

    if [ -n "$SHOW_FILE" ] && [ -s "$SHOW_FILE" ]
    then
        COUNTS=$(
            awk -F '\t' '
                FILENAME == ARGV[1] {
                    show[$1] = 1
                    next
                }

                FILENAME == ARGV[2] && show[$1] {
                    if ($2 == "committed") committed++
                    else if ($2 == "staged") staged++
                    else if ($2 == "unstaged") unstaged++
                    else if ($2 == "both") { staged++; unstaged++ }
                    else if ($2 == "untracked") untracked++
                    else if ($2 == "conflict") conflict++
                }

                END {
                    print committed + 0, staged + 0, unstaged + 0, untracked + 0, conflict + 0
                }
            ' "$SHOW_FILE" "$STATE_FILE"
        )
    else
        COUNTS=$(
            awk -F '\t' -v start="$RANGE_START" -v end="$RANGE_END" '
                $1 >= start && $1 <= end {
                    if ($2 == "committed") committed++
                    else if ($2 == "staged") staged++
                    else if ($2 == "unstaged") unstaged++
                    else if ($2 == "both") { staged++; unstaged++ }
                    else if ($2 == "untracked") untracked++
                    else if ($2 == "conflict") conflict++
                }

                END {
                    print committed + 0, staged + 0, unstaged + 0, untracked + 0, conflict + 0
                }
            ' "$STATE_FILE"
        )
    fi

    set -- $COUNTS
    COMMITTED_COUNT=${1:-0}
    STAGED_COUNT=${2:-0}
    UNSTAGED_COUNT=${3:-0}
    UNTRACKED_COUNT=${4:-0}
    CONFLICT_COUNT=${5:-0}

    if [ "$COMMITTED_COUNT" -eq 0 ] &&
       [ "$STAGED_COUNT" -eq 0 ] &&
       [ "$UNSTAGED_COUNT" -eq 0 ] &&
       [ "$UNTRACKED_COUNT" -eq 0 ] &&
       [ "$CONFLICT_COUNT" -eq 0 ]
    then
        return
    fi

    printf 'STATE  '
    FIRST_STATE=1

    if [ "$COMMITTED_COUNT" -gt 0 ]
    then
        printf '%b◆ %s%b committed' "$UI_MAGENTA" "$COMMITTED_COUNT" "$UI_RESET"
        FIRST_STATE=0
    fi

    if [ "$STAGED_COUNT" -gt 0 ]
    then
        if [ "$FIRST_STATE" -eq 0 ]; then printf ' · '; fi
        printf '%b✚ %s%b staged' "$UI_CYAN" "$STAGED_COUNT" "$UI_RESET"
        FIRST_STATE=0
    fi

    if [ "$UNSTAGED_COUNT" -gt 0 ]
    then
        if [ "$FIRST_STATE" -eq 0 ]; then printf ' · '; fi
        printf '%b✎ %s%b unstaged' "$UI_YELLOW" "$UNSTAGED_COUNT" "$UI_RESET"
        FIRST_STATE=0
    fi

    if [ "$UNTRACKED_COUNT" -gt 0 ]
    then
        if [ "$FIRST_STATE" -eq 0 ]; then printf ' · '; fi
        printf '%b? %s%b untracked' "$UI_CYAN" "$UNTRACKED_COUNT" "$UI_RESET"
        FIRST_STATE=0
    fi

    if [ "$CONFLICT_COUNT" -gt 0 ]
    then
        if [ "$FIRST_STATE" -eq 0 ]; then printf ' · '; fi
        printf '%b✖ %s%b conflict' "$UI_RED" "$CONFLICT_COUNT" "$UI_RESET"
    fi

    printf '\n'
}

render_compare_header()
{
    LINE_WIDTH=$1

    # Row layout is:
    #   <REF> <LINE> │ <STATE2> │ <CODE>
    # STATE2 is always exactly two visible terminal cells, wrapped in
    # one literal padding cell on each side. ANSI escapes are excluded
    # from every width calculation.
    STATE_START=$((LINE_WIDTH + 6))
    HEADER_GAP=$((STATE_START - 4))
    ARROW_GAP=$((STATE_START - 2))

    if [ "$HEADER_GAP" -lt 1 ]; then HEADER_GAP=1; fi
    if [ "$ARROW_GAP" -lt 1 ]; then ARROW_GAP=1; fi

    printf '%bREF%b' "$UI_DIM" "$UI_RESET"
    printf '%*s' "$HEADER_GAP" ''
    printf '%bSTATE%b\n' "$UI_DIM" "$UI_RESET"

    printf '%b↓%b' "$UI_CYAN" "$UI_RESET"
    printf '%*s' "$ARROW_GAP" ''
    printf '%b↓↓%b\n\n' "$UI_CYAN" "$UI_RESET"
}

render_compare_lines()
{
    FILE=$1
    MARKER_FILE=$2
    STATE_FILE=$3
    RANGE_START=$4
    RANGE_END=$5
    SHOW_FILE=${6:-}

    DISPLAY_MAX=$RANGE_END

    if [ -n "$SHOW_FILE" ] && [ -s "$SHOW_FILE" ]
    then
        DISPLAY_MAX=$(tail -n 1 "$SHOW_FILE")
    fi

    LINE_WIDTH=${#DISPLAY_MAX}
    if [ "$LINE_WIDTH" -lt 2 ]; then LINE_WIDTH=2; fi

    render_compare_header "$LINE_WIDTH"

    awk \
        -F '\t' \
        -v start="$RANGE_START" \
        -v end="$RANGE_END" \
        -v width="$LINE_WIDTH" \
        -v use_show="$([ -n "$SHOW_FILE" ] && printf 1 || printf 0)" \
        -v dim="$UI_DIM" \
        -v green="$UI_GREEN" \
        -v yellow="$UI_YELLOW" \
        -v red="$UI_RED" \
        -v cyan="$UI_CYAN" \
        -v magenta="$UI_MAGENTA" \
        -v reset="$UI_RESET" \
        '
        FILENAME == ARGV[1] {
            ref_marker[$1] = $2
            next
        }

        FILENAME == ARGV[2] {
            lifecycle[$1] = $2
            next
        }

        FILENAME == ARGV[3] {
            show[$1] = 1
            next
        }

        FILENAME == ARGV[4] {
            if (FNR < start || FNR > end)
                next

            if (use_show && !show[FNR])
                next

            if (use_show && previous_line > 0 && FNR > previous_line + 1)
                printf "%*s   %s⋮%s\n", width + 3, "", dim, reset

            kind = ref_marker[FNR]
            ref = " "
            ref_color = ""

            if (kind == "+") {
                ref = "+"
                ref_color = green
            } else if (kind == "~") {
                ref = "~"
                ref_color = yellow
            }

            state = lifecycle[FNR]
            if (state == "")
                state = "clean"

            printf "%s%s%s %s%*d%s │ ", ref_color, ref, reset, dim, width, FNR, reset

            # Exactly two visible STATE cells. No ANSI escape sequence is
            # counted as layout width because padding is literal.
            if (state == "committed")
                printf "%s◆%s ", magenta, reset
            else if (state == "staged")
                printf "%s✚%s ", cyan, reset
            else if (state == "unstaged")
                printf " %s✎%s", yellow, reset
            else if (state == "both")
                printf "%s✚%s%s✎%s", cyan, reset, yellow, reset
            else if (state == "untracked")
                printf "%s?%s ", cyan, reset
            else if (state == "conflict")
                printf "%s✖%s ", red, reset
            else
                printf "%s✔%s ", green, reset

            printf " │ %s\n", $0
            previous_line = FNR
        }
        ' \
        "$MARKER_FILE" \
        "$STATE_FILE" \
        "${SHOW_FILE:-/dev/null}" \
        "$FILE"
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
    COMPARE_REF=${3:-}
    COMPARE_LABEL=${4:-}

    if [ ! -f "$FILE" ]
    then
        ui_warn "File does not exist: $FILE"
        return
    fi

    FILE_LINES=$(awk 'END { print NR + 0 }' "$FILE")

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

    MARKER_MODE="clean"
    FILE_STATE="clean"

    if [ -n "$COMPARE_REF" ]
    then
        MARKER_MODE="ref"
        FILE_STATE="WORKTREE ↔ $COMPARE_LABEL"
    else
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

        if [ "$FILE_UNTRACKED" -eq 1 ]
        then
            MARKER_MODE="untracked"
            FILE_STATE="untracked"
        elif [ "$FILE_UNSTAGED" -eq 1 ] && [ "$FILE_STAGED" -eq 1 ]
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

    RF_MARKER_FILE=$(mktemp 2>/dev/null)
    RF_REMOVAL_FILE=$(mktemp 2>/dev/null)

    if [ -z "$RF_MARKER_FILE" ] || [ ! -f "$RF_MARKER_FILE" ] ||
       [ -z "$RF_REMOVAL_FILE" ] || [ ! -f "$RF_REMOVAL_FILE" ]
    then
        rm -f "$RF_MARKER_FILE" "$RF_REMOVAL_FILE"
        ui_warn "Could not create diff marker files for $FILE"
        return
    fi

    if [ "$MARKER_MODE" != "clean" ]
    then
        build_diff_markers \
            "$FILE" \
            "$MARKER_MODE" \
            "$RF_MARKER_FILE" \
            "$RF_REMOVAL_FILE" \
            "$COMPARE_REF"
    else
        : > "$RF_MARKER_FILE"
        : > "$RF_REMOVAL_FILE"
    fi

    ADDED_COUNT=$(
        awk -F '\t' -v start="$RANGE_START" -v end="$RANGE_END" \
            '$1 >= start && $1 <= end && $2 == "+" { count++ } END { print count + 0 }' \
            "$RF_MARKER_FILE"
    )

    MODIFIED_COUNT=$(
        awk -F '\t' -v start="$RANGE_START" -v end="$RANGE_END" \
            '$1 >= start && $1 <= end && $2 == "~" { count++ } END { print count + 0 }' \
            "$RF_MARKER_FILE"
    )

    REMOVED_COUNT=$(
        awk -F '\t' -v start="$RANGE_START" -v end="$RANGE_END" -v file_lines="$FILE_LINES" '
            {
                anchor = $1 + 0
                if (anchor < 1) anchor = 1
                if (file_lines > 0 && anchor > file_lines) anchor = file_lines
                if (anchor >= start && anchor <= end) total += $2
            }
            END { print total + 0 }
        ' "$RF_REMOVAL_FILE"
    )

    # Explicit REF comparison gets the full Git lifecycle view.
    if [ -n "$COMPARE_REF" ]
    then
        STATE_FILE=$(mktemp 2>/dev/null)
        SHOW_FILE=$(mktemp 2>/dev/null)

        if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ] ||
           [ -z "$SHOW_FILE" ] || [ ! -f "$SHOW_FILE" ]
        then
            rm -f "$RF_MARKER_FILE" "$RF_REMOVAL_FILE" "$STATE_FILE" "$SHOW_FILE"
            ui_warn "Could not create lifecycle files for $FILE"
            return
        fi

        build_lifecycle_states \
            "$FILE" \
            "$RF_MARKER_FILE" \
            "$STATE_FILE" \
            "$FILE_LINES"

        if [ -z "$REQUESTED_RANGE" ]
        then
            if [ "$ADDED_COUNT" -eq 0 ] &&
               [ "$MODIFIED_COUNT" -eq 0 ] &&
               [ "$REMOVED_COUNT" -eq 0 ]
            then
                rm -f "$RF_MARKER_FILE" "$RF_REMOVAL_FILE" "$STATE_FILE" "$SHOW_FILE"
                return
            fi

            build_hunk_selection \
                "$RF_MARKER_FILE" \
                "$RF_REMOVAL_FILE" \
                "$FILE_LINES" \
                "$SHOW_FILE"

            printf '\n'
            ui_section "$FILE · WORKTREE ↔ $COMPARE_LABEL · changed hunks"

            render_compare_lines \
                "$FILE" \
                "$RF_MARKER_FILE" \
                "$STATE_FILE" \
                1 \
                "$FILE_LINES" \
                "$SHOW_FILE"

            render_ref_summary \
                "$ADDED_COUNT" \
                "$MODIFIED_COUNT" \
                "$REMOVED_COUNT"

            render_lifecycle_summary \
                "$STATE_FILE" \
                1 \
                "$FILE_LINES" \
                "$SHOW_FILE"
        else
            printf '\n'
            ui_section "$FILE · WORKTREE ↔ $COMPARE_LABEL · lines $RANGE_START-$RANGE_END"

            render_compare_lines \
                "$FILE" \
                "$RF_MARKER_FILE" \
                "$STATE_FILE" \
                "$RANGE_START" \
                "$RANGE_END"

            if [ "$ADDED_COUNT" -eq 0 ] &&
               [ "$MODIFIED_COUNT" -eq 0 ] &&
               [ "$REMOVED_COUNT" -eq 0 ]
            then
                printf '\n'
                ui_ok "No differences in selected range."
            else
                render_ref_summary \
                    "$ADDED_COUNT" \
                    "$MODIFIED_COUNT" \
                    "$REMOVED_COUNT"
            fi

            render_lifecycle_summary \
                "$STATE_FILE" \
                "$RANGE_START" \
                "$RANGE_END"
        fi

        if [ "$REMOVED_COUNT" -gt 0 ]
        then
            ui_muted "removed lines are summarized because they no longer exist in the current file"
        fi

        rm -f "$RF_MARKER_FILE" "$RF_REMOVAL_FILE" "$STATE_FILE" "$SHOW_FILE"
        return
    fi

    # Legacy/current-HEAD file inspection remains compact and range-oriented.
    printf '\n'

    if [ -n "$REQUESTED_RANGE" ]
    then
        ui_section "$FILE · lines $RANGE_START-$RANGE_END · $FILE_STATE"
    else
        ui_section "$FILE · lines 1-$FILE_LINES · $FILE_STATE"
    fi

    if [ "$FILE_STAGED" -eq 1 ] && [ "$FILE_UNSTAGED" -eq 1 ]
    then
        ui_muted "line markers show unstaged working-tree changes"
        printf '\n'
    fi

    LINE_WIDTH=${#RANGE_END}
    if [ "$LINE_WIDTH" -lt 2 ]; then LINE_WIDTH=2; fi

    awk \
        -F '\t' \
        -v start="$RANGE_START" \
        -v end="$RANGE_END" \
        -v width="$LINE_WIDTH" \
        -v dim="$UI_DIM" \
        -v green="$UI_GREEN" \
        -v yellow="$UI_YELLOW" \
        -v reset="$UI_RESET" \
        '
        FILENAME == ARGV[1] {
            marker[$1] = $2
            next
        }

        FILENAME == ARGV[2] && FNR >= start && FNR <= end {
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

            printf "%s%s%s %s%*d%s │ %s\n", \
                color, prefix, reset, dim, width, FNR, reset, $0
        }
        ' \
        "$RF_MARKER_FILE" \
        "$FILE"

    if [ "$ADDED_COUNT" -gt 0 ] ||
       [ "$MODIFIED_COUNT" -gt 0 ] ||
       [ "$REMOVED_COUNT" -gt 0 ]
    then
        render_marker_summary \
            "$ADDED_COUNT" \
            "$MODIFIED_COUNT" \
            "$REMOVED_COUNT"
    fi

    if [ "$REMOVED_COUNT" -gt 0 ]
    then
        ui_muted "removed lines are summarized because they no longer exist in the current file"
    fi

    rm -f "$RF_MARKER_FILE" "$RF_REMOVAL_FILE"
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
# MACHINE-READABLE SNAPSHOT
# ============================================================

if [ "${1:-}" = "--json" ]
then
    shift
    JSON_SCOPE="worktree"

    if [ "${1:-}" = "--staged" ]
    then
        JSON_SCOPE="staged"
        shift
    fi

    if [ "$#" -ne 0 ]
    then
        printf 'STATUSMAN ERROR: --json accepts only the optional --staged flag.\n' >&2
        exit 1
    fi

    if command -v python >/dev/null 2>&1
    then
        PYTHON=python
    elif command -v python3 >/dev/null 2>&1
    then
        PYTHON=python3
    else
        printf 'STATUSMAN ERROR: Python was not found in PATH.\n' >&2
        exit 1
    fi

    PYTHONDONTWRITEBYTECODE=1 \
        PYTHONPATH="$ROOT_DIR${PYTHONPATH:+:$PYTHONPATH}" \
        exec "$PYTHON" -m tools.codelaxy.snapshot_cli \
            --repository "$ROOT_DIR" \
            --scope "$JSON_SCOPE"
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
COMPARE_REF=""
COMPARE_LABEL=""
FILE_ARGUMENT_COUNT=$#

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
        FILE_ARGUMENT_COUNT=$((FILE_ARGUMENT_COUNT - 1))
    elif resolve_compare_ref "$LAST_ARGUMENT"
    then
        COMPARE_REF=$RESOLVED_COMPARE_REF
        COMPARE_LABEL=$RESOLVED_COMPARE_LABEL
        FILE_ARGUMENT_COUNT=$((FILE_ARGUMENT_COUNT - 1))

        if [ "$FILE_ARGUMENT_COUNT" -gt 0 ]
        then
            RANGE_CANDIDATE=""
            CURRENT_ARGUMENT=0

            for ARG
            do
                CURRENT_ARGUMENT=$((CURRENT_ARGUMENT + 1))

                if [ "$CURRENT_ARGUMENT" -eq "$FILE_ARGUMENT_COUNT" ]
                then
                    RANGE_CANDIDATE=$ARG
                    break
                fi
            done

            if is_line_range "$RANGE_CANDIDATE"
            then
                REQUESTED_RANGE=$RANGE_CANDIDATE
                FILE_ARGUMENT_COUNT=$((FILE_ARGUMENT_COUNT - 1))
            fi
        fi
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
    if [ "$AHEAD" -eq 0 ] &&
       [ "$BEHIND" -eq 0 ]
    then
        SYNC_LABEL="sync"
    else
        SYNC_LABEL="↑$AHEAD ↓$BEHIND"
    fi
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
    render_changes_header

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
# COMPARE CONTEXT
# ============================================================

if [ -n "$COMPARE_REF" ]
then
    COMPARE_OID=$(
        git rev-parse --short=7 "$COMPARE_REF" 2>/dev/null ||
        printf 'unknown\n'
    )

    printf '\n'
    ui_section "COMPARE"
    ui_info "worktree ↔ $COMPARE_LABEL · $COMPARE_OID"

    if [ -s "$INSPECTION_FILES" ]
    then
        if [ -n "$REQUESTED_RANGE" ]
        then
            while IFS= read -r FILE
            do
                ui_muted "$FILE · lines $REQUESTED_RANGE"
            done < "$INSPECTION_FILES"
        else
            while IFS= read -r FILE
            do
                render_compare_file_stat "$FILE" "$COMPARE_REF"
            done < "$INSPECTION_FILES"
        fi
    else
        COMPARE_STAT=$(
            git diff --shortstat "$COMPARE_REF" -- |
            sed 's/^[[:space:]]*//'
        )

        if [ -n "$COMPARE_STAT" ]
        then
            ui_muted "$COMPARE_STAT"
        else
            ui_ok "No differences against $COMPARE_LABEL."
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
        render_file \
            "$FILE" \
            "$REQUESTED_RANGE" \
            "$COMPARE_REF" \
            "$COMPARE_LABEL"
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
