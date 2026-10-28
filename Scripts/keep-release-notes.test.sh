#!/bin/sh
# Exercises keep-release-notes.sh against fake changelogs. Run from anywhere: sh Scripts/keep-release-notes.test.sh
set -u

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/keep-release-notes.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

# check NAME EXPECTED_EXIT EXPECTED_STDOUT MODE CHANGELOG
check() {
    name="$1"; expected="$2"; expected_out="$3"; shift 3
    if sh "$script" "$@" >"$work/out" 2>"$work/err"; then actual=0; else actual=$?; fi
    if [ "$actual" -eq "$expected" ] && [ "$(cat "$work/out")" = "$expected_out" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name (exit $actual, expected $expected)"; cat "$work/out" "$work/err"; failures=$((failures + 1))
    fi
}

cat > "$work/released.md" <<'EOF'
# Changelog

## 1.2.0 (2026-10-28)

### Added

- A thing.

## 1.1.0 (2026-01-02)

- Older thing.
EOF
check "version of a dated entry" 0 "1.2.0" version "$work/released.md"
check "notes stop at the next entry" 0 "$(printf '### Added\n\n- A thing.')" notes "$work/released.md"

cat > "$work/unreleased.md" <<'EOF'
# Changelog

## 1.3.0 (unreleased)

- Work in progress.

## 1.2.0 (2026-10-28)

- A thing.
EOF
check "unreleased top entry fails" 1 "" version "$work/unreleased.md"
check "unreleased top entry has no notes" 1 "" notes "$work/unreleased.md"

printf '# Changelog\n\n## 1.2 (2026-10-28)\n\n- Short version.\n' > "$work/short.md"
check "two-part version fails" 1 "" version "$work/short.md"

printf '# Changelog\n\n## v1.2.0 (2026-10-28)\n\n- Prefixed.\n' > "$work/prefixed.md"
check "v-prefixed version fails" 1 "" version "$work/prefixed.md"

printf '# Changelog\n\n## 1.2.0 (2026-10-28)\n\n\n## 1.1.0 (2026-01-02)\n\n- Older.\n' > "$work/empty.md"
check "empty entry fails" 1 "" notes "$work/empty.md"

printf '# Changelog\n\nNothing yet.\n' > "$work/none.md"
check "changelog without entries fails" 1 "" version "$work/none.md"

check "missing changelog fails closed" 1 "" version "$work/missing.md"

cp "$work/released.md" "$work/unreadable.md"
chmod 000 "$work/unreadable.md"
check "unreadable changelog fails closed" 1 "" version "$work/unreadable.md"
chmod 644 "$work/unreadable.md"

check "unknown mode fails" 1 "" publish "$work/released.md"

check "next minor resets patch" 0 "1.3.0" next minor 1.2.4
check "next patch" 0 "1.2.5" next patch 1.2.4
check "next major resets minor and patch" 0 "2.0.0" next major 1.2.4
check "next from 0.1.1 minor is 0.2.0" 0 "0.2.0" next minor 0.1.1
check "next with unknown bump fails" 1 "" next huge 1.2.4
check "next with two-part version fails" 1 "" next minor 1.2
check "next with v-prefixed version fails" 1 "" next minor v1.2.4
check "next with no version fails" 1 "" next minor

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"
