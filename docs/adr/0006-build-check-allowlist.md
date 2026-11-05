# 6. Build check allowlist

Date: 2026-11-05

## Status

Accepted.

## Context

`Scripts/keep-verify-excluded.sh` checked only the configurations named in `KEEP_FORBIDDEN_CONFIGURATIONS`, which defaulted to `Release`. A configuration with another name, such as Pilot, Production, Beta or a renamed Release, was never checked, so a build that linked Keep in it passed. The script also read only the main executable and the dylibs beside it. Keep inside an embedded framework or a plug-in passed. A `find` error or an unreadable file was not treated as a failure in every case.

Non-negotiable 1 says Keep never ships in production. Non-negotiable 4 says safety checks fail closed. Both are weaker than they should be.

## Decision

- The check is an allowlist. `KEEP_ALLOWED_CONFIGURATIONS` names the configurations that may contain Keep. Its default is `Debug`. Every other configuration is checked. Names are separated by semicolons, and spaces around them are ignored.
- An empty `CONFIGURATION` fails the build.
- `KEEP_FORBIDDEN_CONFIGURATIONS` is deprecated. A configuration listed there is checked even when it is allowed. It works for one release, with a warning, and is then removed.
- The check scans every regular Mach-O file under the frameworks and plug-ins folders, as well as the executable and the dylibs beside it. A file is recognised as Mach-O by its magic number. A folder that cannot be listed, or a file that cannot be read, fails the build.
- Matching is byte-wise (`LC_ALL=C`) and fixed-string. In a UTF-8 locale, `grep` could miss a marker that sits next to the invalid bytes of a Mach-O header.

## Why an allowlist

An allowlist makes a new configuration safe by default. A configuration that nobody has thought about is checked, and it fails the build unless it is listed. A forbidden list fails open: the configuration that is missed is the one that ships.

Failing a build is cheap. Shipping Keep to customers is not, which is the reason for non-negotiable 4.

## Migration

Integrators whose internal configurations have `KEEP_ENABLED` must list them in `KEEP_ALLOWED_CONFIGURATIONS`, for example `Debug;Development;UAT`. Until they do, those configurations fail the build. Replace `KEEP_FORBIDDEN_CONFIGURATIONS` with the allowlist. It still works for one release, but it prints a warning.

## Consequences

- A breaking change for integrators. It ships as a minor release, as ADR 0004 requires for changes that break pre-1.0 callers.
- Builds fail for any internal configuration that is not listed. That is intended.
- The check takes longer for apps with large frameworks, because every Mach-O file under them is read. This is acceptable for a build phase.
- The script depends on `od`, `find` and `grep` from the macOS toolchain, as before.
- The production exclusion itself is unchanged. Pilot and Production still exclude Keep and viewer dependency objects.
