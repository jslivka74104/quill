# `phase3-hardening` TDD evidence

Date: 2026-08-03
Status: **Local GREEN; pinned CI pending an authorized push**

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
- The first full parallel Swift run then exposed scheduler-sensitive timing in
  the main-actor responsiveness assertion. Test-only checkpoint `332d862`
  (`test: stabilize recording responsiveness timing`) widened the blocking
  fixture and preserved a clear fail/pass margin. Two consecutive full runs
  and the coverage run passed afterward.

## Result

- `transcript.json` and `transcript.md` use the existing private atomic writer;
  both are atomically replaced and verified at `0600`.
- The retired-hook validator rejects direct `system` calls, Darwin module
  aliases, `import func Darwin.system`, and `@_silgen_name("system")` bindings
  while preserving Quill's legitimate `.system` track-role vocabulary.
- Architecture scripts validate every read as UTF-8 and pass without relying
  on `LANG` or `LC_ALL`.
- The architecture baseline and governing rules now record Accepted status.
- The Phase 2 evidence records successful pinned CI run `30772479939` at
  commit `1d9d991`; the original Phase 3 evidence now states its former
  explicit UTF-8 locale precondition.

## Final local verification

- Production build: **PASS**.
- Full Swift suite: **43 tests in 9 suites, PASS**, twice consecutively after
  timing stabilization.
- Coverage-instrumented Swift suite: **43 tests in 9 suites, PASS**.
- Architecture contract suite: **13 runs, 64 assertions, PASS** under default,
  POSIX, unset-locale, and forced-US-ASCII checks.
- Architecture schema/link validator: **PASS** under default and unset locale.
- Remove-on-stop adversarial suite: **14 runs, 113 assertions, PASS** under
  default and POSIX locales.
- Retired-hook validator: **PASS** under default and POSIX locales.
- Swift parser check across all Phase 3 changed Swift files: **PASS**.
- `git diff --check`: **PASS**.
- Gitleaks: **54 commits scanned, no findings**; the final uncommitted evidence
  diff was also scanned with no findings.

Coverage reports 83.94% for `RecordingSession.swift`, 85.71% for
`RecordingRootPreflight.swift`, and 91.47% for `SessionLifecycle.swift`, or
86.47% combined across those three lifecycle core files. Every executable line
in the remediated `Transcript.write(to:)` path ran. Repository-wide source line
coverage is 50.56%; no repository-wide 80% claim is made.

Local Swift execution used the documented Command Line Tools compatibility
framework, writable module caches, disabled SwiftPM sandbox, and the installed
macOS 15.4 SDK. Those are host accommodations, not product or CI settings.
Pinned macOS 15 / Xcode 16.4 CI remains pending because this branch has not
been pushed.
