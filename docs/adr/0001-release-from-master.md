# 1. Release from master on merge

Date: 2026-10-27

## Status

Accepted

## Context

Work lands on `develop`. `master` existed but had not been updated since the first CI commit, and `v0.0.1` was tagged by hand on a `develop` commit. The ReadME told users to pin a `main` branch that does not exist, and CI's pull-request trigger pointed at the same missing branch, so pull requests were never checked before merge.

Swift Package Manager users resolve Keep from git tags or a branch, so a release is a tag on a commit that passed CI.

## Decision

- `master` is the release branch. `develop` stays the default branch and the base for feature work.
- Every merge into `master` is a release. `.github/workflows/release.yml` runs the full build and test workflow on the merged commit, then tags it `vX.Y.Z` and publishes a GitHub release.
- The version and release notes come from the top entry of `CHANGELOG.md`, which must read `## X.Y.Z (YYYY-MM-DD)`. `Scripts/keep-release-notes.sh` parses it and fails closed: an undated (`unreleased`) entry, a malformed heading, an empty entry or an unreadable file stops the release.
- Pull requests into `master` run a `release-check` job that applies the same rules and fails if `vX.Y.Z` is already tagged, so a bad release PR is caught before it merges.
- If the tag already exists on the merged commit (a re-run after a partial failure), the workflow finishes the release instead of failing. If it exists on another commit, the workflow fails.

## Consequences

- A merge into `master` that does not bump the changelog fails the release workflow. Hotfixes need their own changelog entry.
- Releases cannot be tagged by hand without bypassing this flow. `v0.0.1` predates it.
- `master` should be protected (require the Build Validation checks, no direct pushes) so the only way in is a reviewed release PR. This is a repository setting, not something the workflow enforces.
- The release job uses the workflow's `GITHUB_TOKEN`. Tags it pushes do not trigger other workflows, which is fine because nothing runs on tags.
