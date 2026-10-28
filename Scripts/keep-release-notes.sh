#!/bin/sh
#
# Reads the top entry of CHANGELOG.md for the release and change workflows.
#
#   keep-release-notes.sh version [changelog]                 prints X.Y.Z of a dated entry
#   keep-release-notes.sh notes [changelog]                   prints the body of a dated entry
#   keep-release-notes.sh pending [changelog]                 prints X.Y.Z of an "(unreleased)" entry
#   keep-release-notes.sh bump [changelog]                    prints patch or minor for the top entry
#   keep-release-notes.sh next major|minor|patch CURRENT      prints the version after CURRENT (X.Y.Z)
#
# The first "## " heading is "## X.Y.Z (YYYY-MM-DD)" for a release, or "## X.Y.Z (unreleased)" while its
# changes are still in develop. version and notes need the dated form, so release.yml only publishes a
# release. bump reads either form, and never prints major: the release:major label chooses that.
#
# bump reads the "### " headings of the top entry. Fixed and Security make a patch. Added, Changed,
# Removed, Deprecated and Breaking changes make a minor, because Keep is pre-1.0 and semver allows
# breaking changes in a minor release there. Any other heading is an error.
#
# This script fails closed: an unreadable changelog, a missing or malformed heading, an empty entry,
# an unknown heading, or a malformed version is an error, so nothing is released by accident.
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
    version | notes | pending | bump) ;;
    *) fail "usage: $0 version|notes|pending|bump [changelog] | next major|minor|patch CURRENT" ;;
esac

[ -f "$changelog" ] && [ -r "$changelog" ] || fail "cannot read $changelog"

# body prints the lines under the first "## " heading, up to the next one.
body() {
    awk 'found && /^## / { exit } found { print } /^## / { found = 1 }' "$changelog"
}

heading="$(grep -m 1 '^## ' "$changelog")" || fail "no \"## \" release heading in $changelog"
dated_version="$(printf '%s\n' "$heading" | sed -nE 's/^## ([0-9]+\.[0-9]+\.[0-9]+) \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$/\1/p')"
unreleased_version="$(printf '%s\n' "$heading" | sed -nE 's/^## ([0-9]+\.[0-9]+\.[0-9]+) \(unreleased\)$/\1/p')"

case "$mode" in
    version | notes)
        [ -n "$dated_version" ] || fail "the top entry must be \"## X.Y.Z (YYYY-MM-DD)\", found \"$heading\""
        ;;
    pending)
        [ -n "$unreleased_version" ] || fail "the top entry must be \"## X.Y.Z (unreleased)\", found \"$heading\""
        ;;
    bump)
        [ -n "$dated_version$unreleased_version" ] || fail "the top entry must be \"## X.Y.Z (YYYY-MM-DD)\" or \"## X.Y.Z (unreleased)\", found \"$heading\""
        ;;
esac

case "$mode" in
    version)
        echo "$dated_version"
        ;;
    pending)
        echo "$unreleased_version"
        ;;
    notes)
        notes="$(body | sed '/[^[:space:]]/,$!d')"
        printf '%s' "$notes" | grep -q '[^[:space:]]' || fail "the $dated_version entry has no notes"
        printf '%s\n' "$notes"
        ;;
    bump)
        headings="$(body | sed -n '/^###/p')"
        [ -n "$headings" ] || fail "the top entry has no \"### \" headings"
        kind=patch
        while IFS= read -r line; do
            case "$line" in
                "### Fixed" | "### Security") ;;
                "### Added" | "### Changed" | "### Removed" | "### Deprecated" | "### Breaking changes") kind=minor ;;
                *) fail "unknown heading \"$line\" in the top entry" ;;
            esac
        done <<EOF
$headings
EOF
        echo "$kind"
        ;;
esac
