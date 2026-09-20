#!/bin/sh

# Codelaxy runtime boundary.
#
# Shell tools use POSIX paths. Native Windows children receive a Windows path
# for TMPDIR, TEMP, and TMP through codelaxy_native_exec(). Nothing here
# depends on a particular MSYS2 installation directory.

codelaxy_runtime_init()
{
    if [ "${CODELAXY_RUNTIME_READY:-0}" = "1" ] &&
       [ -n "${CODELAXY_RUNTIME_SESSION:-}" ] &&
       [ -d "${CODELAXY_TEMP_DIR:-}" ] &&
       [ -d "${CODELAXY_SNAPSHOT_DIR:-}" ]
    then
        return 0
    fi

    if [ -n "${CODELAXY_RUNTIME_ROOT:-}" ]
    then
        CODELAXY_RUNTIME_BASE=$CODELAXY_RUNTIME_ROOT
    else
        CODELAXY_GIT_DIR=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) ||
            return 1

        if command -v cygpath >/dev/null 2>&1
        then
            CODELAXY_GIT_DIR=$(cygpath -u "$CODELAXY_GIT_DIR") || return 1
        fi

        CODELAXY_RUNTIME_BASE="$CODELAXY_GIT_DIR/codelaxy/runtime"
    fi

    # The override is a one-hop boundary for snapshots without Git metadata.
    # Do not leak it into unrelated child repositories.
    unset CODELAXY_RUNTIME_ROOT

    mkdir -p "$CODELAXY_RUNTIME_BASE/sessions" || return 1

    CODELAXY_RUNTIME_BASE=$(
        CDPATH= cd -- "$CODELAXY_RUNTIME_BASE" && pwd
    ) || return 1

    CODELAXY_RUNTIME_SESSION=$(
        mktemp -d "$CODELAXY_RUNTIME_BASE/sessions/session.XXXXXX"
    ) || return 1

    CODELAXY_TEMP_DIR="$CODELAXY_RUNTIME_SESSION/temp"
    CODELAXY_SNAPSHOT_DIR="$CODELAXY_RUNTIME_SESSION/snapshots"

    if ! mkdir -p "$CODELAXY_TEMP_DIR" "$CODELAXY_SNAPSHOT_DIR"
    then
        codelaxy_runtime_cleanup
        return 1
    fi

    TMPDIR=$CODELAXY_TEMP_DIR

    if command -v cygpath >/dev/null 2>&1
    then
        CODELAXY_NATIVE_TEMP=$(cygpath -m "$CODELAXY_TEMP_DIR") || {
            codelaxy_runtime_cleanup
            return 1
        }
    else
        CODELAXY_NATIVE_TEMP=$CODELAXY_TEMP_DIR
    fi

    TEMP=$CODELAXY_NATIVE_TEMP
    TMP=$CODELAXY_NATIVE_TEMP
    CODELAXY_RUNTIME_READY=1

    export TMPDIR TEMP TMP
    return 0
}

codelaxy_runtime_cleanup()
{
    case "${CODELAXY_RUNTIME_SESSION:-}" in
        "${CODELAXY_RUNTIME_BASE:-}"/sessions/session.*)
            if [ -d "$CODELAXY_RUNTIME_SESSION" ]
            then
                rm -rf "$CODELAXY_RUNTIME_SESSION"
            fi
            ;;
    esac

    CODELAXY_RUNTIME_READY=0
    CODELAXY_RUNTIME_SESSION=
    CODELAXY_TEMP_DIR=
    CODELAXY_SNAPSHOT_DIR=
    CODELAXY_NATIVE_TEMP=
}

codelaxy_native_exec()
{
    if [ "${CODELAXY_RUNTIME_READY:-0}" != "1" ] ||
       [ -z "${CODELAXY_NATIVE_TEMP:-}" ]
    then
        return 1
    fi

    TMPDIR=$CODELAXY_NATIVE_TEMP \
        TEMP=$CODELAXY_NATIVE_TEMP \
        TMP=$CODELAXY_NATIVE_TEMP \
        "$@"
}

codelaxy_temp_file()
{
    CODELAXY_TEMP_PREFIX=${1:-temp}

    case "$CODELAXY_TEMP_PREFIX" in
        *[!A-Za-z0-9._-]*) return 1 ;;
    esac

    mktemp "$CODELAXY_TEMP_DIR/$CODELAXY_TEMP_PREFIX.XXXXXX"
}

codelaxy_temp_dir()
{
    CODELAXY_TEMP_PREFIX=${1:-temp}

    case "$CODELAXY_TEMP_PREFIX" in
        *[!A-Za-z0-9._-]*) return 1 ;;
    esac

    mktemp -d "$CODELAXY_TEMP_DIR/$CODELAXY_TEMP_PREFIX.XXXXXX"
}

codelaxy_snapshot_dir()
{
    CODELAXY_SNAPSHOT_PREFIX=${1:-snapshot}

    case "$CODELAXY_SNAPSHOT_PREFIX" in
        *[!A-Za-z0-9._-]*) return 1 ;;
    esac

    mktemp -d "$CODELAXY_SNAPSHOT_DIR/$CODELAXY_SNAPSHOT_PREFIX.XXXXXX"
}
