# `phase3-hardening` TDD evidence

Date: 2026-08-03
Status: **Local and pinned Xcode 16.4 CI GREEN**

## Scope

This remediation closes Phase 3 findings F8–F10 and corrects the stale
architecture/CI records identified by the adversarial review. It protects
transcript artifacts, closes two source-validator bypasses, and makes the
architecture gates independent of Ruby's ambient external encoding.

## RED → GREEN

- RED `5bf77f6` (`test: expose phase 3 hardening gaps`) produced only the
  intended failures after the test harness itself was validated:
  - the focused transcript test reported both artifacts were not `0600`;
  - the remove-on-stop suite reported that a direct Darwin `system` function
    import and alias bypassed validation;
  - the architecture suite reported two failures: governing documents still
    marked Proposed and an invalid-byte-sequence crash under forced US-ASCII.
- GREEN `59cbeb4` (`fix: close phase 3 hardening gaps`) passed the focused
  transcript test, both security validators, and the Ruby suites in default,
  POSIX, unset-locale, and forced-US-ASCII environments.
- Follow-up RED `6671b36` (`test: expose transcription log permissions`)
  reproduced `transcribe.log` creation through the real unreadable-manifest
  recovery path and observed a non-private mode. GREEN `08a210c` (`fix: secure
  transcription diagnostics`) moved append logging to private atomic
  replacement and passed both transcription-recovery tests.
- The first full parallel Swift run exposed scheduler-sensitive timing in the
  main-actor responsiveness assertion. Test-only checkpoint `332d862`
  (`test: stabilize recording responsiveness timing`) widened the blocking
  fixture, after which two consecutive local runs and the coverage run passed.
- Pinned run `30827663118` at `47dc34c` then provided the first Xcode 16.4 RED:
  strict concurrency rejected a main-actor-isolated, non-Sendable test fixture
  crossing into `RecordingSessionController`. Checkpoint `0b941e0` isolated
  only the heartbeat on `MainActor`, preserving the production sendability
  boundary.
- Pinned run `30828087503` compiled all tests and exposed a second RED: the
  recorder-deadline test used a `< 60 ms` wall-clock threshold and measured
  about 95 ms under parallel runner load. Checkpoint `3bc98b7` replaced that
  threshold with an ordering guarantee: the session authors `start_timeout`
  while the deliberately blocked recorder call has not returned. That test
  passed in pinned run `30828651405`.
- The same run exposed the remaining `< 120 ms` MainActor heartbeat threshold,
  which measured about 313 ms under runner load. Checkpoint `627f027` replaced
  it with a deterministic event-ordering proof. Pinned run `30828962985`
  supplied the final compile-time RED because Xcode 16.4 forbids semaphore
  waits from async contexts. Checkpoint `d25d6c1` uses `AsyncStream` for the
  async-side notification and confines the blocking semaphore to the detached
  recorder thread.
- Pinned run `30829298653` at `d25d6c1` passed the complete Swift 6.1 / Xcode
  16.4 workflow, including all 44 Swift tests and both Ruby contract suites.

## Result

- `transcript.json`, `transcript.md`, and `transcribe.log` use the existing
  private atomic writer; all are atomically replaced and verified at `0600`.
  Existing log files must be regular, non-symlink files before their contents
  are carried into a replacement.
- The retired-hook validator rejects direct `system` calls, Darwin module
  aliases, `import func Darwin.system`, and `@_silgen_name("system")` bindings
  while preserving Quill's legitimate `.system` track-role vocabulary.
- Architecture scripts validate every read as UTF-8 and pass without relying
  on `LANG` or `LC_ALL`.
- The architecture baseline and governing rules now record Accepted status.
- The Phase 2 evidence records successful pinned CI run `30772479939` at
  commit `1d9d991`; the original Phase 3 evidence now states its former
  explicit UTF-8 locale precondition.

## Final verification

- Production build: **PASS**.
- Full Swift suite: **44 tests in 9 suites, PASS**.
- Coverage-instrumented Swift suite: **44 tests in 9 suites, PASS**.
- Architecture contract suite: **13 runs, 64 assertions, PASS** under default,
  POSIX, unset-locale, and forced-US-ASCII checks.
- Architecture schema/link validator: **PASS** under default and unset locale.
- Remove-on-stop adversarial suite: **14 runs, 113 assertions, PASS** under
  default and POSIX locales.
- Retired-hook validator: **PASS** under default and POSIX locales.
- Swift parser check across all Phase 3 changed Swift files: **PASS**.
- `git diff --check`: **PASS**.
- Gitleaks: **full history scanned, no findings**; the testing-evidence
  directory was also scanned with no findings.
- GitHub Actions run `30829298653`: **PASS** on macOS 15 with Swift 6.1 /
  Xcode 16.4 at `d25d6c1`.

Coverage reports 83.94% for `RecordingSession.swift`, 85.71% for
`RecordingRootPreflight.swift`, and 91.47% for `SessionLifecycle.swift`, or
86.47% combined across those three lifecycle core files. Every executable line
in the remediated `Transcript.write(to:)` path ran. Repository-wide source line
coverage is 50.94%; no repository-wide 80% claim is made.

Local Swift execution used the documented Command Line Tools compatibility
framework, writable module caches, disabled SwiftPM sandbox, and the installed
macOS 15.4 SDK. Those are host accommodations, not product or CI settings.
The authoritative pinned lane runs plain `swift test` on macOS 15 with Xcode
16.4 and is green.
