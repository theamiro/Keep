#!/bin/sh
#
# Fails the build if Keep is present in a configuration that must never contain it.
#
# Add as a "Run Script" build phase on the app target, after the link step, with
# "$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)" as an input path (Xcode's script sandbox blocks reads otherwise).
# Xcode provides CONFIGURATION, TARGET_BUILD_DIR, EXECUTABLE_PATH, EXECUTABLE_FOLDER_PATH,
# FRAMEWORKS_FOLDER_PATH and UNLOCALIZED_RESOURCES_FOLDER_PATH.
# KEEP_FORBIDDEN_CONFIGURATIONS is a semicolon-separated list of configuration names (default: "Release").
#
# This script fails closed: if it cannot read the executable, the build fails rather than passing.
#
set -eu

forbidden="${KEEP_FORBIDDEN_CONFIGURATIONS:-Release}"
configuration="${CONFIGURATION:-}"

is_forbidden=0
old_ifs="$IFS"
IFS=';'
for name in $forbidden; do
    if [ "$name" = "$configuration" ]; then
        is_forbidden=1
    fi
done
IFS="$old_ifs"

if [ "$is_forbidden" -eq 0 ]; then
    exit 0
fi

failures=0
executable="${TARGET_BUILD_DIR:-}/${EXECUTABLE_PATH:-}"

if [ ! -f "$executable" ]; then
    echo "error: cannot verify Keep is excluded: executable not found at $executable"
    exit 1
fi

# Markers that only appear when Keep's code is linked. Debug builds keep app code in a *.debug.dylib,
# so every dylib next to the executable is scanned too.
targets="$executable"
for dylib in "${TARGET_BUILD_DIR:-}/${EXECUTABLE_FOLDER_PATH:-}"/*.dylib; do
    if [ -f "$dylib" ]; then
        targets="$targets $dylib"
    fi
done

for target in $targets; do
    for marker in '_TtC4Keep' '$s4Keep' 'com.keep.core' 'crash-snapshot.bin' 'com.keep.urlprotocol.handled'; do
        # grep exits 0 on a match, 1 on no match, and 2 on error. An error must never count as "no match".
        status=0
        grep -a -q -- "$marker" "$target" || status=$?
        case "$status" in
            0)
                echo "error: Keep is linked into the $configuration build (found '$marker' in $target). Exclude Keep from this configuration: set EXCLUDED_SOURCE_FILE_NAMES = Keep.o and remove Keep from the app's frameworks."
                failures=$((failures + 1))
                ;;
            1) ;;
            *)
                echo "error: cannot read $target to verify Keep is excluded (grep status $status)"
                failures=$((failures + 1))
                ;;
        esac
    done
done

for artifact in \
    "${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}/Keep.framework" \
    "${TARGET_BUILD_DIR:-}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}/Keep_Keep.bundle"; do
    if [ -e "$artifact" ]; then
        echo "error: Keep artifact found in the $configuration build: $artifact"
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    exit 1
fi
echo "Keep verification passed for $configuration."
