#!/bin/sh
# Exercises keep-verify-excluded.sh against fake app bundles. Run from anywhere: sh Scripts/keep-verify-excluded.test.sh
set -u

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/keep-verify-excluded.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

check() {
    name="$1"; expected="$2"; shift 2
    if env "$@" "$script" >"$work/out" 2>&1; then actual=0; else actual=$?; fi
    if [ "$actual" -eq "$expected" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name (exit $actual, expected $expected)"; cat "$work/out"; failures=$((failures + 1))
    fi
}

mkdir -p "$work/clean" "$work/dirty"
printf 'plain executable bytes' > "$work/clean/App"
printf 'bytes com.keep.core more bytes' > "$work/dirty/App"

check "release without keep passes" 0 CONFIGURATION=Release TARGET_BUILD_DIR="$work/clean" EXECUTABLE_PATH=App
check "release with keep fails" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/dirty" EXECUTABLE_PATH=App
check "debug with keep is allowed by default" 0 CONFIGURATION=Debug TARGET_BUILD_DIR="$work/dirty" EXECUTABLE_PATH=App
check "custom forbidden list catches debug" 1 CONFIGURATION=Debug KEEP_FORBIDDEN_CONFIGURATIONS="Pilot Debug;Debug" TARGET_BUILD_DIR="$work/dirty" EXECUTABLE_PATH=App
check "configuration names with spaces match" 1 "CONFIGURATION=Production Release" "KEEP_FORBIDDEN_CONFIGURATIONS=Pilot Release;Production Release" TARGET_BUILD_DIR="$work/dirty" EXECUTABLE_PATH=App

mkdir -p "$work/clean/frameworks/Keep.framework"
check "release with Keep.framework fails" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/clean" EXECUTABLE_PATH=App FRAMEWORKS_FOLDER_PATH=frameworks
rm -rf "$work/clean/frameworks"

mkdir -p "$work/clean/frameworks/Runestone.framework"
check "release with Runestone.framework fails" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/clean" EXECUTABLE_PATH=App FRAMEWORKS_FOLDER_PATH=frameworks
rm -rf "$work/clean/frameworks"

mkdir -p "$work/clean/resources/Runestone_Runestone.bundle"
check "release with Runestone resources fails" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/clean" EXECUTABLE_PATH=App UNLOCALIZED_RESOURCES_FOLDER_PATH=resources
rm -rf "$work/clean/resources"

mkdir -p "$work/runestone-object"
printf 'object code $s9Runestone TextView' > "$work/runestone-object/App"
check "release with Runestone object code fails" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/runestone-object" EXECUTABLE_PATH=App

mkdir -p "$work/unreadable"
printf 'plain' > "$work/unreadable/App"
chmod 000 "$work/unreadable/App"
check "unreadable executable fails closed" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/unreadable" EXECUTABLE_PATH=App
chmod 644 "$work/unreadable/App"

check "missing executable fails closed" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/missing" EXECUTABLE_PATH=App

mkdir -p "$work/debugdylib"
printf 'stub' > "$work/debugdylib/App"
printf 'code com.keep.core' > "$work/debugdylib/App.debug.dylib"
check "release with Keep in a debug dylib fails" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/debugdylib" EXECUTABLE_PATH=App EXECUTABLE_FOLDER_PATH=

mkdir -p "$work/with space/clean" "$work/with space/dirty"
printf 'plain executable bytes' > "$work/with space/clean/App"
printf 'bytes com.keep.core more bytes' > "$work/with space/dirty/App"
check "build directory with spaces passes when clean" 0 CONFIGURATION=Release TARGET_BUILD_DIR="$work/with space/clean" EXECUTABLE_PATH=App
check "build directory with spaces still detects Keep" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/with space/dirty" EXECUTABLE_PATH=App

mkdir -p "$work/dylib space/App.app"
printf 'stub' > "$work/dylib space/App.app/App"
printf 'code com.keep.core' > "$work/dylib space/App.app/App.debug.dylib"
check "debug dylib in a path with spaces is scanned" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/dylib space" EXECUTABLE_PATH=App.app/App EXECUTABLE_FOLDER_PATH=App.app

# Allowlist: every configuration not listed is checked, and listed names are trimmed.
check "unlisted configuration with keep fails" 1 CONFIGURATION=Pilot TARGET_BUILD_DIR="$work/dirty" EXECUTABLE_PATH=App
check "listed configuration with keep is allowed" 0 "CONFIGURATION=UAT" "KEEP_ALLOWED_CONFIGURATIONS=Debug; UAT" TARGET_BUILD_DIR="$work/dirty" EXECUTABLE_PATH=App
check "allowed names ignore spaces around them" 0 CONFIGURATION=Development "KEEP_ALLOWED_CONFIGURATIONS= Debug ;  Development  " TARGET_BUILD_DIR="$work/dirty" EXECUTABLE_PATH=App
check "allowed names must match exactly" 1 CONFIGURATION=Deb KEEP_ALLOWED_CONFIGURATIONS=Debug TARGET_BUILD_DIR="$work/dirty" EXECUTABLE_PATH=App
check "empty configuration fails closed" 1 CONFIGURATION= TARGET_BUILD_DIR="$work/clean" EXECUTABLE_PATH=App

# Frameworks and plug-ins: every Mach-O file under them is scanned, and an unreadable one fails.
mkdir -p "$work/nested/frameworks/Lib.framework" "$work/nested/plugins/Ext.appex"
printf 'plain' > "$work/nested/App"
printf 'plain' > "$work/nested/frameworks/Lib.framework/Lib"
printf 'plain' > "$work/nested/plugins/Ext.appex/Ext"
check "clean nested frameworks and plug-ins pass" 0 CONFIGURATION=Release TARGET_BUILD_DIR="$work/nested" EXECUTABLE_PATH=App FRAMEWORKS_FOLDER_PATH=frameworks PLUGINS_FOLDER_PATH=plugins

printf '\317\372\355\376 com.keep.core' > "$work/nested/frameworks/Lib.framework/Lib"
check "keep inside an embedded framework fails" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/nested" EXECUTABLE_PATH=App FRAMEWORKS_FOLDER_PATH=frameworks PLUGINS_FOLDER_PATH=plugins
check "keep is found under a UTF-8 locale too" 1 LC_ALL=en_US.UTF-8 CONFIGURATION=Release TARGET_BUILD_DIR="$work/nested" EXECUTABLE_PATH=App FRAMEWORKS_FOLDER_PATH=frameworks PLUGINS_FOLDER_PATH=plugins
printf 'plain' > "$work/nested/frameworks/Lib.framework/Lib"

printf '\317\372\355\376 com.keep.core' > "$work/nested/plugins/Ext.appex/Ext"
check "keep inside a plug-in fails" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/nested" EXECUTABLE_PATH=App FRAMEWORKS_FOLDER_PATH=frameworks PLUGINS_FOLDER_PATH=plugins
printf 'plain' > "$work/nested/plugins/Ext.appex/Ext"

printf 'com.keep.core in a text file' > "$work/nested/frameworks/Lib.framework/notes.txt"
check "files that are not Mach-O are not scanned" 0 CONFIGURATION=Release TARGET_BUILD_DIR="$work/nested" EXECUTABLE_PATH=App FRAMEWORKS_FOLDER_PATH=frameworks PLUGINS_FOLDER_PATH=plugins
rm -f "$work/nested/frameworks/Lib.framework/notes.txt"

printf '\317\372\355\376' > "$work/nested/frameworks/Lib.framework/Locked"
chmod 000 "$work/nested/frameworks/Lib.framework/Locked"
check "unreadable file in a framework fails closed" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/nested" EXECUTABLE_PATH=App FRAMEWORKS_FOLDER_PATH=frameworks PLUGINS_FOLDER_PATH=plugins
chmod 644 "$work/nested/frameworks/Lib.framework/Locked"
rm -f "$work/nested/frameworks/Lib.framework/Locked"

mkdir -p "$work/nested/frameworks/Sealed.framework"
chmod 000 "$work/nested/frameworks/Sealed.framework"
check "folder that cannot be listed fails closed" 1 CONFIGURATION=Release TARGET_BUILD_DIR="$work/nested" EXECUTABLE_PATH=App FRAMEWORKS_FOLDER_PATH=frameworks PLUGINS_FOLDER_PATH=plugins
chmod 755 "$work/nested/frameworks/Sealed.framework"

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"
