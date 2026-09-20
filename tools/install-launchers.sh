#!/usr/bin/env bash

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE="$SCRIPT_DIR/bin/statusman"
DESTINATION=${CODELAXY_BIN_DIR:-"$HOME/.local/bin"}

if [ "$#" -gt 1 ]
then
    printf 'Usage: bash tools/install-launchers.sh [BIN_DIRECTORY]\n' >&2
    exit 2
fi

if [ "$#" -eq 1 ]
then
    DESTINATION=$1
fi

if [ ! -f "$SOURCE" ]
then
    printf 'CODELAXY ERROR: canonical launcher was not found.\n' >&2
    exit 1
fi

mkdir -p "$DESTINATION" || exit 1

for TOOL in statusman mrproper ironman doorman
do
    TARGET="$DESTINATION/$TOOL"
    TEMP_TARGET="$DESTINATION/.$TOOL.new.$$"

    if ! cp "$SOURCE" "$TEMP_TARGET" ||
       ! chmod +x "$TEMP_TARGET" ||
       ! mv -f "$TEMP_TARGET" "$TARGET"
    then
        rm -f "$TEMP_TARGET"
        printf 'CODELAXY ERROR: could not install %s.\n' "$TARGET" >&2
        exit 1
    fi
done

printf 'Installed Codelaxy launchers in %s\n' "$DESTINATION"
