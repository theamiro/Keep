# 4. Release version from the CHANGELOG headings

Date: 2026-10-28

## Status

Accepted. Supersedes the version rule in [0003](0003-release-from-main.md).

## Context

ADR 0003 made every release a minor version by default. A `release:patch` label chose a patch. A fix-only release therefore became 0.X.0 unless someone remembered the label, and the version did not follow the change.

`release-check` ran only on pull requests into `main`. A wrong version on `develop` was found when the release PR was opened, not when the feature PR was merged.

## Decision

- The bump comes from the `### ` headings of the top CHANGELOG entry. `Fixed` and `Security` make a patch. `Added`, `Changed`, `Removed`, `Deprecated` and `Breaking changes` make a minor. Any other heading fails the check, and so does an entry with no headings.
- `Breaking changes` make a minor. Keep is pre-1.0, and semver allows breaking changes in a minor release before 1.0.0.
- A major release is never inferred. A PR with the `release:major` label makes a major. It is the only way to get a major version, including after 1.0.0.
- A PR into `main` is a release. Its head must be `develop`. Its top entry must be dated, `## X.Y.Z (YYYY-MM-DD)`, and name the bump after the latest `vX.Y.Z` tag. The `release:patch` label has no effect and is removed.
- A PR into `develop` checks a top entry that is `## X.Y.Z (unreleased)` against the same rule. A feature added to a `0.2.1` entry therefore fails until the heading says `0.3.0`. A dated top entry is already released, so it is not checked.
- `Scripts/keep-release-notes.sh` implements the rule. `bump` reads either heading form. `pending` reads an unreleased version. `version` and `notes` still require a dated entry, so `release.yml` is unchanged.

## Consequences

- The version is still chosen by the author, in the CHANGELOG heading. The check now enforces the rule from the headings, so a fix can no longer be published as a minor release by accident.
- Authors choose headings by what the change does. The notes already describe the same things, so this adds no new writing.
- A change that needs a major version must have the `release:major` label. The check cannot infer it.
- The `release:patch` label should be deleted from the repository. `release:major` stays.
- `release-check` must be a required check on `main`, set in the repository rules. It should also be required on `develop` if the rules allow it, so that the unreleased version is checked before the release PR.
- Keep's release PRs are still merged with a merge commit, as ADR 0003 decided.
