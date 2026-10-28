#!/bin/sh
#
# Reads the release at the top of CHANGELOG.md for the release workflow.
#
#   keep-release-notes.sh version [changelog]                 prints X.Y.Z
#   keep-release-notes.sh notes [changelog]                   prints the body of that entry
#   keep-release-notes.sh next major|minor|patch CURRENT      prints the version after CURRENT (X.Y.Z)
#
# The first "## " heading must be "## X.Y.Z (YYYY-MM-DD)". An "(unreleased)" entry is not a release.
#
# This script fails closed: an unreadable changelog, a missing or undated heading, an empty entry,
# or a malformed version is an error, so nothing is released by accident.
#
set -eu

fail() {
    echo "keep-release-notes: $1" >&2
    exit 1
}

mode="${1:-}"

if [ "$mode" = next ]; then
    kind="${2:-}"
    current="${3:-}"
    printf '%s\n' "$current" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "current version must be X.Y.Z, found \"$current\""
    major="${current%%.*}"
    rest="${current#*.}"
    minor="${rest%%.*}"
    patch="${rest#*.}"
    case "$kind" in
        major) echo "$((major + 1)).0.0" ;;
        minor) echo "$major.$((minor + 1)).0" ;;
        patch) echo "$major.$minor.$((patch + 1))" ;;
        *) fail "bump must be major, minor or patch, found \"$kind\"" ;;
    esac
    exit 0
fi

changelog="${2:-CHANGELOG.md}"

case "$mode" in
    version | notes) ;;
    *) fail "usage: $0 version|notes [changelog] | next major|minor|patch CURRENT" ;;
esac

[ -f "$changelog" ] && [ -r "$changelog" ] || fail "cannot read $changelog"

heading="$(grep -m 1 '^## ' "$changelog")" || fail "no \"## \" release heading in $changelog"
version="$(printf '%s\n' "$heading" | sed -nE 's/^## ([0-9]+\.[0-9]+\.[0-9]+) \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$/\1/p')"
[ -n "$version" ] || fail "the top entry must be \"## X.Y.Z (YYYY-MM-DD)\", found \"$heading\""

if [ "$mode" = version ]; then
    echo "$version"
    exit 0
fi

notes="$(awk 'found && /^## / { exit } found { print } /^## / { found = 1 }' "$changelog" | sed '/[^[:space:]]/,$!d')"
printf '%s' "$notes" | grep -q '[^[:space:]]' || fail "the $version entry has no notes"
printf '%s\n' "$notes"
