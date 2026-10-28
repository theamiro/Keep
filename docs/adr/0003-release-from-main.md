# 3. Release from main on merge, minor by default

Date: 2026-10-28

## Status

Accepted. Supersedes [0001](0001-release-from-master.md). Its version rule (minor by default, chosen by label) is superseded by [0004](0004-semver-bump-from-changelog.md).

## Context

ADR 0001 made `master` the release branch. The repository's default branch is now `main`, and `master` is being removed. The release workflow runs on pushes to its trigger branch, so a workflow that names a branch that is not the one merged into never runs.

Release 0.1.2 (PR #17) merged into `master`, but its release job failed because the top CHANGELOG entry was still `unreleased`. The merge published nothing, and the failure was only visible after the merge. The pre-merge `release-check` job had failed too, but it was not a required check, so the PR merged anyway. `actions/checkout@v4` also runs on Node 20, which GitHub is retiring.

## Decision

- `main` is the release branch. Every merge into it is a release, as ADR 0001 decided. Feature work still targets `develop`.
- The release PR goes from `develop` into `main`. Its top CHANGELOG entry is dated, `## X.Y.Z (YYYY-MM-DD)`, which is what release.yml reads.
- Releases are minor versions by default. `release-check` computes the expected version as the minor bump of the latest `vX.Y.Z` tag. A `release:patch` or `release:major` label on the PR selects the other bumps. The check fails if the CHANGELOG names any other version.
- `release-check` runs on pull requests into `main`, before the merge, so a wrong version fails while it is still cheap to fix. `release.yml` publishes the release after the merge.
- Workflows use `actions/checkout@v7`, which runs on Node 24.

## Consequences

- The version is still written by hand in the release PR, but the check enforces the default. The date is written in the same PR, so the release needs no commit to `main` from a workflow.
- The `release:patch` and `release:major` labels must exist in the repository.
- `release-check` must be a required status check on `main`, set in the repository rules. The workflow cannot enforce that itself.
- Release PRs are merged with a merge commit, not a squash, so `main`'s history stays inside `develop`.
- If a merge reaches `main` without passing `release-check`, `release.yml` fails after the merge and publishes nothing. Recovery is a fixing PR into `main`.
