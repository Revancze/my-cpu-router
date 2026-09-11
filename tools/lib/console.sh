#!/bin/sh

# ============================================================
# CPU ROUTER - CONSOLE UI
# ============================================================

if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]
then
    UI_RESET=""
    UI_BOLD=""
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

    UI_RED="${UI_ESC}[1;31m"
    UI_GREEN="${UI_ESC}[1;32m"
    UI_YELLOW="${UI_ESC}[1;33m"
    UI_BLUE="${UI_ESC}[1;34m"
    UI_MAGENTA="${UI_ESC}[1;35m"
    UI_CYAN="${UI_ESC}[1;36m"
    UI_WHITE="${UI_ESC}[1;37m"
fi

ui_rule()
{
    printf '%s\n' \
        "------------------------------------------------------------"
}

ui_banner()
{
    title=$1
    primary=$2
    secondary=$3

    printf '\n'
    printf '%b%s%b\n' \
        "$primary" \
        "+==========================================================+" \
        "$UI_RESET"

    printf '%b|%b %b%-56s%b %b|%b\n' \
        "$primary" \
        "$UI_RESET" \
        "${secondary}${UI_BOLD}" \
        "$title" \
        "$UI_RESET" \
        "$primary" \
        "$UI_RESET"

    printf '%b%s%b\n' \
        "$primary" \
        "+==========================================================+" \
        "$UI_RESET"

    printf '\n'
}

ui_section()
{
    printf '%b%s%b\n' \
        "${UI_BOLD}${UI_WHITE}" \
        "$1" \
        "$UI_RESET"

    ui_rule
}

ui_ok()
{
    printf '%b[ OK ]%b %s\n' \
        "$UI_GREEN" \
        "$UI_RESET" \
        "$1"
}

ui_fixed()
{
    printf '%b[FIXED]%b %s\n' \
        "$UI_YELLOW" \
        "$UI_RESET" \
        "$1"
}

ui_fail()
{
    printf '%b[FAIL]%b %s\n' \
        "$UI_RED" \
        "$UI_RESET" \
        "$1"
}

ui_info()
{
    printf '%b[INFO]%b %s\n' \
        "$UI_CYAN" \
        "$UI_RESET" \
        "$1"
}

ui_mrproper_banner()
{
    ui_banner \
        "MRPROPER :: WORKTREE CLEANUP" \
        "$UI_CYAN" \
        "$UI_GREEN"
}

ui_ironman_banner()
{
    ui_banner \
        "IRONMAN :: VERIFICATION SUITE" \
        "$UI_RED" \
        "$UI_YELLOW"
}

ui_doorman_banner()
{
    ui_banner \
        "DOORMAN :: COMMIT GATE" \
        "$UI_BLUE" \
        "$UI_MAGENTA"
}
