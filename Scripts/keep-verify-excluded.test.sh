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

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"
