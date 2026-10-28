#!/bin/sh
# Exercises the Runestone resource cleanup used by non-debug sample builds.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/keep-strip-viewer-resources.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

check_absent() {
    name="$1"
    if [ ! -e "$2" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name"
        failures=$((failures + 1))
    fi
}

mkdir -p "$work/Release/App.app/Runestone_Runestone.bundle" \
    "$work/Release/App.app/TreeSitterLanguages_TreeSitterJSONQueries.bundle" \
    "$work/Release/App.app/Keep_Keep.bundle" \
    "$work/Debug/App.app/Runestone_Runestone.bundle"

CONFIGURATION=Release TARGET_BUILD_DIR="$work/Release" UNLOCALIZED_RESOURCES_FOLDER_PATH=App.app "$script"
check_absent "release Runestone resources removed" "$work/Release/App.app/Runestone_Runestone.bundle"
check_absent "release query resources removed" "$work/Release/App.app/TreeSitterLanguages_TreeSitterJSONQueries.bundle"
if [ -d "$work/Release/App.app/Keep_Keep.bundle" ]; then
    echo "ok   unrelated bundle preserved"
else
    echo "FAIL unrelated bundle preserved"
    failures=$((failures + 1))
fi

CONFIGURATION=Debug TARGET_BUILD_DIR="$work/Debug" UNLOCALIZED_RESOURCES_FOLDER_PATH=App.app "$script"
if [ -d "$work/Debug/App.app/Runestone_Runestone.bundle" ]; then
    echo "ok   debug resources preserved"
else
    echo "FAIL debug resources preserved"
    failures=$((failures + 1))
fi

if CONFIGURATION=Release TARGET_BUILD_DIR="$work/missing" UNLOCALIZED_RESOURCES_FOLDER_PATH=App.app "$script" >/dev/null 2>&1; then
    echo "FAIL missing release resources fail closed"
    failures=$((failures + 1))
else
    echo "ok   missing release resources fail closed"
fi

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"
