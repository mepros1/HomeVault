# Publication review — 2026-10-13

## Scope and status

Source snapshot prepared from the local HomeVault project for a first public GitHub
repository. Both the Flutter Android app and Java backend were developed by the
author using AI-assisted development. Current product status: local prototype.
No production rollout, real purchase flow, APK build, or device execution was
performed in this review.

The original directory and its Git history were not changed. The publication copy
starts a new Git repository containing only the selected current source files.
The original Git history was not accessible to the Git command in this environment
and has not been copied or certified as free of credentials.

## Changes

- Added a portfolio-oriented README, architecture diagram, local mock-mode setup,
  explicit prototype status, and release limitations.
- Added the MIT License at the author's request; retained the Noto Sans OFL notice.
- Excluded `.env`, signing material, machine-specific configuration, IDE caches,
  build outputs, and generated Dart/localization files.
- Added a tracked-file publication check and a CI job for it. It detects selected
  credential paths/signatures, not every possible secret or a complete history.
- Device token renewal now requires a separate random 256-bit credential. The
  client persists it before registration; the server stores its SHA-256 hash and
  atomically refuses an existing id with a different secret. Migration V4 adds
  the column. Legacy identities need an authenticated migration or fresh local
  setup; no silent ownership reassignment is allowed.
- Network rate-limit responses no longer attempt to parse missing monthly quota
  fields. Analysis jobs remain queued for a later retry.
- PDF replacement quota calculations subtract the old report size.
- Bound development PostgreSQL to localhost.
- Marked policy materials as drafts and corrected an unsupported zero-retention
  claim for the AI provider. See [provider terms](https://ai.google.dev/gemini-api/terms).

## Verification actually performed

- Java compilation succeeded with Java 21 and the locally cached Maven dependencies.
- Backend suite: **30 tests attempted; 29 passed, 0 assertion failures, 1 environment
  error**. New device-credential and PDF-replacement tests passed.
- The remaining test is `GoogleServiceAccountTest.parsesTheKeyFileAndSignsAVerifiableAssertion`.
  Creating its HTTP client fails with `Unable to establish loopback connection`
  / `Permission denied: connect` under this session's network restrictions.
  This is not recorded as a passing full suite. Run it again in normal CI.
- Mockito's agent was supplied explicitly during this review to avoid a blocked
  dynamic attach. The repository does not embed this machine's agent path.
- Flutter/Dart analysis and tests could not be executed: the local runtime failed
  with a path canonicalization/resolved-executable permission error. These checks
  remain required. New mobile tests are included but are not claimed as passing.
- No real PostgreSQL migration/concurrency test, Android build, emulator test,
  live Gemini call, Play Integrity exchange, purchase, or deployment was run.

CI retains the full backend suite and Flutter checks. The environment-restricted
test has not been removed or silently skipped from the published project.

## Findings requiring further work

See [release-limitations.md](release-limitations.md). The main remaining issues
are concurrent analysis reservation, cache request context, atomic backup limits,
billing event ordering, exceptional mobile queue recovery, and production-specific
privacy/retention/release configuration. Source publication does not resolve them.
