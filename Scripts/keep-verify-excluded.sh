#!/bin/sh
#
# Fails the build if Keep is present in a configuration that is not allowed to contain it.
#
# Add as a "Run Script" build phase on the app target, after the link step, with
# "$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)" as an input path (Xcode's script sandbox blocks reads otherwise).
# Xcode provides CONFIGURATION, TARGET_BUILD_DIR, EXECUTABLE_PATH, EXECUTABLE_FOLDER_PATH,
# FRAMEWORKS_FOLDER_PATH, PLUGINS_FOLDER_PATH and UNLOCALIZED_RESOURCES_FOLDER_PATH.
#
# KEEP_ALLOWED_CONFIGURATIONS is a semicolon-separated list of the configurations that may contain Keep (default: "Debug").
# Every other configuration is checked. Spaces around each name are ignored.
# KEEP_FORBIDDEN_CONFIGURATIONS is deprecated. A configuration listed there is checked even when it is allowed. It works
# for one release, then goes.
#
# This script fails closed: an empty CONFIGURATION, a missing executable, and a file or folder that cannot be read or
# listed each fail the build rather than pass it.
#
set -eu
# Byte-wise matching. In a UTF-8 locale, grep can miss a marker next to the invalid bytes of a Mach-O header.
LC_ALL=C
export LC_ALL

allowed="${KEEP_ALLOWED_CONFIGURATIONS:-Debug}"
forced="${KEEP_FORBIDDEN_CONFIGURATIONS:-}"
configuration="${CONFIGURATION:-}"

# Succeeds when the second argument is one of the semicolon-separated names in the first.
is_listed() {
    rest="$1;"
    while [ -n "$rest" ]; do
        item="${rest%%;*}"
        rest="${rest#*;}"
        item="${item#"${item%%[! ]*}"}"
        item="${item%"${item##*[! ]}"}"
        if [ -n "$item" ] && [ "$item" = "$2" ]; then
            return 0
        fi
    done
    return 1
}

if [ -z "$configuration" ]; then
    echo "error: cannot verify Keep is excluded: CONFIGURATION is empty"
    exit 1
fi

if [ -n "$forced" ]; then
    echo "warning: KEEP_FORBIDDEN_CONFIGURATIONS is deprecated. Configurations are checked unless listed in KEEP_ALLOWED_CONFIGURATIONS."
fi

must_check=1
if is_listed "$allowed" "$configuration"; then
    must_check=0
fi
if [ -n "$forced" ] && is_listed "$forced" "$configuration"; then
    must_check=1
fi

if [ "$must_check" -eq 0 ]; then
    exit 0
fi

failures=0
executable="${TARGET_BUILD_DIR:-}/${EXECUTABLE_PATH:-}"

if [ ! -f "$executable" ]; then
    echo "error: cannot verify Keep is excluded: executable not found at $executable"
    exit 1
fi

# Scans one file for Keep's markers. Each path is passed as a single argument, so spaces are safe.
scan_file() {
    target="$1"
    for marker in \
        '_TtC4Keep' '$s4Keep' 'com.keep.core' 'crash-snapshot.bin' 'com.keep.urlprotocol.handled' \
        '_TtC9Runestone' '$s9Runestone' 'tree_sitter_json' 'TreeSitterJSONRunestone'; do
        # grep exits 0 on a match, 1 on no match, and 2 on error. An error must never count as "no match".
        status=0
        grep -a -F -q -- "$marker" "$target" || status=$?
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
}

# Succeeds (0) for a Mach-O file, fails (1) for any other readable file, and returns 2 when the file cannot be read.
is_macho() {
    # The status is od's, so a failed read is not hidden by the pipe that strips the spaces.
    magic="$(od -An -tx1 -N4 "$1")" || return 2
    magic="$(printf '%s' "$magic" | tr -d ' \n')"
    case "$magic" in
        feedface | feedfacf | cefaedfe | cffaedfe | cafebabe | bebafeca) return 0 ;;
    esac
    return 1
}

# Scans every regular Mach-O file under a bundle folder, including nested frameworks and plug-ins. A folder that
# cannot be listed, or a file that cannot be read, is a failure, not a pass.
scan_tree() {
    dir="$1"
    if [ ! -d "$dir" ]; then
        return 0
    fi
    if ! files="$(find "$dir" -type f -print)"; then
        echo "error: cannot list $dir to verify Keep is excluded"
        failures=$((failures + 1))
        return 0
    fi
    while IFS= read -r file; do
        status=0
        is_macho "$file" || status=$?
        case "$status" in
            0) scan_file "$file" ;;
            1) ;;
            *)
                echo "error: cannot read $file to verify Keep is excluded"
                failures=$((failures + 1))
                ;;
        esac
    done <<EOF
$files
EOF
}

# Debug builds keep app code in a *.debug.dylib, so every dylib next to the executable is scanned too.
scan_file "$executable"
for dylib in "${TARGET_BUILD_DIR:-}/${EXECUTABLE_FOLDER_PATH:-}"/*.dylib; do
    if [ -f "$dylib" ]; then
        scan_file "$dylib"
    fi
done

if [ -n "${FRAMEWORKS_FOLDER_PATH:-}" ]; then
    scan_tree "${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH}"
fi
if [ -n "${PLUGINS_FOLDER_PATH:-}" ]; then
    scan_tree "${TARGET_BUILD_DIR:-}/${PLUGINS_FOLDER_PATH}"
fi

for artifact in \
    "${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}/Keep.framework" \
    "${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}/Runestone.framework" \
    "${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}/TreeSitterJSONRunestone.framework" \
    "${TARGET_BUILD_DIR:-}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}/Keep_Keep.bundle" \
    "${TARGET_BUILD_DIR:-}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}/Runestone_Runestone.bundle" \
    "${TARGET_BUILD_DIR:-}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}/TreeSitterLanguages_TreeSitterJSONQueries.bundle"; do
    if [ -e "$artifact" ]; then
        echo "error: Keep artifact found in the $configuration build: $artifact"
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    exit 1
fi
echo "Keep verification passed for $configuration."
