#!/bin/sh

# ============================================================
# CODELAXY CONSOLE UI
# Shared terminal design system for project tooling.
# ============================================================

# ------------------------------------------------------------
# COLOR SYSTEM
# ------------------------------------------------------------

if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]
then
    UI_RESET=""
    UI_BOLD=""
    UI_DIM=""

    UI_RED=""
    UI_GREEN=""
    UI_YELLOW=""
    UI_BLUE=""
    UI_MAGENTA=""
    UI_CYAN=""
    UI_WHITE=""
else
    UI_ESC=$(printf '\033')

    UI_RESET="${UI_ESC}[0m"
    UI_BOLD="${UI_ESC}[1m"
    UI_DIM="${UI_ESC}[2m"

    UI_RED="${UI_ESC}[1;31m"
    UI_GREEN="${UI_ESC}[1;32m"
    UI_YELLOW="${UI_ESC}[1;33m"
    UI_BLUE="${UI_ESC}[1;34m"
    UI_MAGENTA="${UI_ESC}[1;35m"
    UI_CYAN="${UI_ESC}[1;36m"
    UI_WHITE="${UI_ESC}[1;37m"
fi

# ------------------------------------------------------------
# LAYOUT
# ------------------------------------------------------------

UI_WIDTH=${CODELAXY_UI_WIDTH:-${COLUMNS:-60}}

case "$UI_WIDTH" in
    ''|*[!0-9]*)
        UI_WIDTH=60
        ;;
esac

if [ "$UI_WIDTH" -lt 52 ]
then
    UI_WIDTH=52
fi

if [ "$UI_WIDTH" -gt 88 ]
then
    UI_WIDTH=88
fi

# ------------------------------------------------------------
# INTERNAL PRIMITIVES
# ------------------------------------------------------------

ui_repeat()
{
    UI_REPEAT_CHAR=$1
    UI_REPEAT_COUNT=$2
    UI_REPEAT_INDEX=0

    case "$UI_REPEAT_COUNT" in
        ''|*[!0-9]*)
            return 0
            ;;
    esac

    while [ "$UI_REPEAT_INDEX" -lt "$UI_REPEAT_COUNT" ]
    do
        printf '%s' "$UI_REPEAT_CHAR"
        UI_REPEAT_INDEX=$((UI_REPEAT_INDEX + 1))
    done
}

ui_rule()
{
    printf '%b' "$UI_DIM"
    ui_repeat "─" "$UI_WIDTH"
    printf '%b\n' "$UI_RESET"
}

ui_panel_bottom()
{
    UI_PANEL_PRIMARY=$1
    UI_PANEL_INNER=$((UI_WIDTH - 2))

    printf '%b╰' "$UI_PANEL_PRIMARY"
    ui_repeat "─" "$UI_PANEL_INNER"
    printf '╯%b\n' "$UI_RESET"
}

ui_panel_meta()
{
    UI_PANEL_META=$1
    UI_PANEL_PRIMARY=$2
    UI_PANEL_SECONDARY=$3

    UI_PANEL_INNER=$((UI_WIDTH - 2))
    UI_PANEL_TEXT=" $UI_PANEL_META"

    UI_PANEL_TEXT_LENGTH=${#UI_PANEL_TEXT}
    UI_PANEL_PADDING=$((UI_PANEL_INNER - UI_PANEL_TEXT_LENGTH))

    if [ "$UI_PANEL_PADDING" -lt 1 ]
    then
        UI_PANEL_PADDING=1
    fi

    printf '%b│%b%b%s%b' \
        "$UI_PANEL_PRIMARY" \
        "$UI_RESET" \
        "$UI_PANEL_SECONDARY" \
        "$UI_PANEL_TEXT" \
        "$UI_RESET"

    ui_repeat " " "$UI_PANEL_PADDING"

    printf '%b│%b\n' \
        "$UI_PANEL_PRIMARY" \
        "$UI_RESET"
}

# ------------------------------------------------------------
# MODERN TOOL HEADER
# ------------------------------------------------------------

ui_tool_header()
{
    UI_HEADER_TOOL=$1
    UI_HEADER_CONTEXT=${2:-}
    UI_HEADER_META=${3:-}
    UI_HEADER_PRIMARY=${4:-$UI_CYAN}
    UI_HEADER_SECONDARY=${5:-$UI_WHITE}

    UI_HEADER_INNER=$((UI_WIDTH - 2))

    UI_HEADER_LEFT="─ $UI_HEADER_TOOL "

    if [ -n "$UI_HEADER_CONTEXT" ]
    then
        UI_HEADER_RIGHT=" $UI_HEADER_CONTEXT ─"
    else
        UI_HEADER_RIGHT="─"
    fi

    UI_HEADER_LEFT_LENGTH=${#UI_HEADER_LEFT}
    UI_HEADER_RIGHT_LENGTH=${#UI_HEADER_RIGHT}

    UI_HEADER_FILL=$(
        printf '%s\n' \
            "$((UI_HEADER_INNER
                - UI_HEADER_LEFT_LENGTH
                - UI_HEADER_RIGHT_LENGTH))"
    )

    if [ "$UI_HEADER_FILL" -lt 1 ]
    then
        UI_HEADER_RIGHT=" ─"
        UI_HEADER_RIGHT_LENGTH=${#UI_HEADER_RIGHT}

        UI_HEADER_FILL=$(
            printf '%s\n' \
                "$((UI_HEADER_INNER
                    - UI_HEADER_LEFT_LENGTH
                    - UI_HEADER_RIGHT_LENGTH))"
        )
    fi

    if [ "$UI_HEADER_FILL" -lt 1 ]
    then
        UI_HEADER_FILL=1
    fi

    printf '\n'

    printf '%b╭%b' \
        "$UI_HEADER_PRIMARY" \
        "$UI_RESET"

    printf '%b%s%b' \
        "${UI_HEADER_SECONDARY}${UI_BOLD}" \
        "$UI_HEADER_LEFT" \
        "$UI_RESET"

    printf '%b' "$UI_HEADER_PRIMARY"
    ui_repeat "─" "$UI_HEADER_FILL"
    printf '%b' "$UI_RESET"

    printf '%b%s%b' \
        "${UI_HEADER_SECONDARY}${UI_BOLD}" \
        "$UI_HEADER_RIGHT" \
        "$UI_RESET"

    printf '%b╮%b\n' \
        "$UI_HEADER_PRIMARY" \
        "$UI_RESET"

    if [ -n "$UI_HEADER_META" ]
    then
        ui_panel_meta \
            "$UI_HEADER_META" \
            "$UI_HEADER_PRIMARY" \
            "${UI_HEADER_SECONDARY}${UI_BOLD}"
    fi

    ui_panel_bottom "$UI_HEADER_PRIMARY"

    printf '\n'
}

# ------------------------------------------------------------
# SECTIONS
# ------------------------------------------------------------

ui_section()
{
    UI_SECTION_NAME=$1
    UI_SECTION_PREFIX=" $UI_SECTION_NAME "
    UI_SECTION_LENGTH=${#UI_SECTION_PREFIX}
    UI_SECTION_FILL=$((UI_WIDTH - UI_SECTION_LENGTH))

    if [ "$UI_SECTION_FILL" -lt 1 ]
    then
        UI_SECTION_FILL=1
    fi

    printf '%b%s%b' \
        "${UI_BOLD}${UI_WHITE}" \
        "$UI_SECTION_PREFIX" \
        "$UI_RESET"

    printf '%b' "$UI_DIM"
    ui_repeat "─" "$UI_SECTION_FILL"
    printf '%b\n' "$UI_RESET"
}

ui_divider()
{
    printf '%b' "$UI_DIM"
    ui_repeat "─" "$UI_WIDTH"
    printf '%b\n' "$UI_RESET"
}

# ------------------------------------------------------------
# STATUS MESSAGES
# ------------------------------------------------------------

ui_ok()
{
    printf '%b✓%b %s\n' \
        "$UI_GREEN" \
        "$UI_RESET" \
        "$1"
}

ui_fixed()
{
    printf '%b↺%b %s\n' \
        "$UI_YELLOW" \
        "$UI_RESET" \
        "$1"
}

ui_warn()
{
    printf '%b!%b %s\n' \
        "$UI_YELLOW" \
        "$UI_RESET" \
        "$1"
}

ui_fail()
{
    printf '%b✕%b %s\n' \
        "$UI_RED" \
        "$UI_RESET" \
        "$1"
}

ui_info()
{
    printf '%b·%b %s\n' \
        "$UI_CYAN" \
        "$UI_RESET" \
        "$1"
}

ui_muted()
{
    printf '%b  %s%b\n' \
        "$UI_DIM" \
        "$1" \
        "$UI_RESET"
}

# ------------------------------------------------------------
# DATA ROWS
# ------------------------------------------------------------

ui_metric()
{
    UI_METRIC_LABEL=$1
    UI_METRIC_VALUE=$2

    printf '  %-28s %s\n' \
        "$UI_METRIC_LABEL" \
        "$UI_METRIC_VALUE"
}

ui_count()
{
    UI_COUNT_LABEL=$1
    UI_COUNT_VALUE=$2

    printf '  %-28s %s\n' \
        "$UI_COUNT_LABEL" \
        "$UI_COUNT_VALUE"
}

ui_change()
{
    UI_CHANGE_KIND=$1
    UI_CHANGE_TEXT=$2

    case "$UI_CHANGE_KIND" in
        add|A|+)
            printf '%b+%b %s\n' \
                "$UI_GREEN" \
                "$UI_RESET" \
                "$UI_CHANGE_TEXT"
            ;;

        delete|D|-)
            printf '%b-%b %s\n' \
                "$UI_RED" \
                "$UI_RESET" \
                "$UI_CHANGE_TEXT"
            ;;

        modify|M|~)
            printf '%b~%b %s\n' \
                "$UI_YELLOW" \
                "$UI_RESET" \
                "$UI_CHANGE_TEXT"
            ;;

        warn|!)
            ui_warn "$UI_CHANGE_TEXT"
            ;;

        *)
            printf '  %s\n' "$UI_CHANGE_TEXT"
            ;;
    esac
}

# ------------------------------------------------------------
# FOOTERS
# ------------------------------------------------------------

ui_footer_ok()
{
    printf '\n'
    ui_divider

    printf '%b✓%b %b%s%b\n' \
        "$UI_GREEN" \
        "$UI_RESET" \
        "$UI_BOLD" \
        "$1" \
        "$UI_RESET"
}

ui_footer_fail()
{
    printf '\n'
    ui_divider

    printf '%b✕%b %b%s%b\n' \
        "$UI_RED" \
        "$UI_RESET" \
        "$UI_BOLD" \
        "$1" \
        "$UI_RESET"
}

# ------------------------------------------------------------
# LEGACY COMPATIBILITY
# ------------------------------------------------------------

ui_banner()
{
    UI_BANNER_TITLE=$1
    UI_BANNER_PRIMARY=$2
    UI_BANNER_SECONDARY=$3

    case "$UI_BANNER_TITLE" in
        *" :: "*)
            UI_BANNER_TOOL=${UI_BANNER_TITLE%% :: *}
            UI_BANNER_CONTEXT=${UI_BANNER_TITLE#* :: }
            ;;

        *)
            UI_BANNER_TOOL=$UI_BANNER_TITLE
            UI_BANNER_CONTEXT=""
            ;;
    esac

    ui_tool_header \
        "$UI_BANNER_TOOL" \
        "$UI_BANNER_CONTEXT" \
        "" \
        "$UI_BANNER_PRIMARY" \
        "$UI_BANNER_SECONDARY"
}

# ------------------------------------------------------------
# TOOL IDENTITIES
# ------------------------------------------------------------

ui_mrproper_banner()
{
    ui_tool_header \
        "MRPROPER" \
        "WORKTREE CLEANUP" \
        "" \
        "$UI_CYAN" \
        "$UI_GREEN"
}

ui_ironman_banner()
{
    ui_tool_header \
        "IRONMAN" \
        "VERIFICATION SUITE" \
        "" \
        "$UI_RED" \
        "$UI_YELLOW"
}

ui_doorman_banner()
{
    ui_tool_header \
        "DOORMAN" \
        "COMMIT GATE" \
        "" \
        "$UI_BLUE" \
        "$UI_MAGENTA"
}

ui_statusman_banner()
{
    ui_tool_header \
        "STATUSMAN" \
        "PROJECT STATUS" \
        "" \
        "$UI_MAGENTA" \
        "$UI_CYAN"
}
