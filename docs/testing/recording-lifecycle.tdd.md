# `recording-lifecycle` TDD evidence

Date: 2026-08-02
Status: **Local GREEN; publishing and packaged-app gates pending**

## Source and scoped interpretation

This change implements only the `recording-lifecycle` step in the
[ordered change plan](../architecture/quill-v2-architecture.md#ordered-change-plan)
under the repository's
[RED → GREEN rules](../architecture/governing-rules.md#change-and-verification-rules).
The separately supplied Phase 3 handoff was treated as planning input and
checked against the accepted architecture, ADR 0002, and the v2 session schema
before use.

Phase 3 writes the smallest schema-valid `session.json` for the current fixed
two-track online-meeting capture: one `part-0001`, a primary system track, a
secondary microphone track, the accepted lifecycle vocabulary, typed session
and track failures, and required timestamps/timebase fields. It does not add
`state.json`, imported parts, annotations, SQLite, bookmarks/remapping, v1
adoption, or the general v2 session store. Those remain assigned to later
ordered changes.

The currently selected recording root remains authoritative for this phase.
Recording start validates it through an injectable capability boundary before
creating a session directory or evidence. This phase does not change the
default root to `~/Quill` and does not add `NSOpenPanel` or sandbox bookmarks.
The capability boundary keeps local/writable volume, privacy-safe location,
private modes, same-directory atomic replacement, file/directory sync, and
capacity reserve independently reportable.

Recorder API return is treated only as "started," never as "live." Promotion
to `recording` requires an injected/testable first-sample signal. Real-time
callback ownership, ring buffers, synchronized fallback, and the deeper
recorder health redesign remain Phase 4 work.

## User journeys

- As a reporter, I need Quill to refuse an unsupported recording root before
  it creates interview evidence.
- As a reporter, I need a private, discoverable `starting` record to exist
  before either requested recorder starts.
- As a reporter, I need successful first-buffer liveness and clean
  finalization to produce truthful `recording` and `complete` transitions.
- As a reporter, I need an observed live-process start failure to be recorded
  as typed `failed`, while a later recovery scan classifies surviving
  non-terminal work only as `interrupted`.
- As a maintainer, I need deterministic failure injection at each lifecycle
  boundary so no incomplete capture is presented as complete.
- As an existing Quill user, I need legacy `meta.json`, transcription resume,
  elapsed-time, capture cleanup, and Phase 2 security behavior to remain
  compatible outside the intentional lifecycle changes.

## Verified test specification

| Guarantee | Test target | Evidence |
|---|---|---|
| Secured directory, audio destinations, and atomic `starting` manifest precede recorder start | `startingManifestAndPrivateDirectoryPrecedeRecorderStart` | Pass |
| Every root capability fails specifically before evidence creation | `refusesEachCapabilityFailureBeforeCreatingEvidence` (six capability arguments) | Pass |
| No live requested track produces an observed typed `failed` transition | `noLiveRecorderWritesObservedTypedFailure` | Pass |
| Recovery alone authors `interrupted` with null session failure | `recoveryAloneAuthorsInterruptedWithoutSessionFailure` (`starting` and `recording`) | Pass |
| First-buffer liveness promotes to `recording`; finalization then persists `complete` | `cleanCapturePromotesOnFirstSampleThenCompletesAfterFinalization` | Pass |
| Initial, failed-state, and terminal persistence failures remain observable and recoverable | Three persistence-failure regression tests | Pass |
| Terminal manifests are byte-immutable under recovery | `terminalManifestRemainsByteImmutable` | Pass |
| Injected crashes leave truthful discoverable state at every lifecycle boundary | `lifecycleCrashMatrixLeavesTruthfulState` (eight crash boundaries) | Pass |
| Real local temporary storage preserves `0700`/`0600` | `productionStorageCreatesAndVerifiesPrivateModes` | Pass |
| Legacy and Phase 2 behavior remains green | Full Swift suite and existing Ruby architecture/security suites | Pass |

## RED → GREEN report

### RED

- Command: local Command Line Tools equivalent of
  `swift test --filter 'Recording(RootPreflight|Lifecycle)Tests'`, with the
  repository's documented SDK/framework/cache accommodations. A temporary,
  ignored compatibility copy of Swift Testing and the ArgumentParser checkout
  was used because this host currently pairs a Swift 6.3 compiler/framework
  with an older SDK; neither accommodation is part of the branch diff.
- Result: the package dependencies and existing `quill` production target
  compiled. The test target then reached the new Phase 3 files and failed
  because `RecordingRootCapability`, `RecordingRootPreflight`,
  `RecordingRootPreflightError`, `AtomicFileWriter`, `RecordingTrackDriver`,
  `SessionManifest`, lifecycle state/failure types, recovery, and injected
  crash-boundary APIs do not exist yet.
- This is the intended compile-time RED: the failure identifies the missing
  deterministic lifecycle and storage-capability contract, not test syntax,
  dependency resolution, or an unrelated regression.
- Checkpoint: `43facdd` (`test: add recording lifecycle crash contracts`).

### GREEN

- Initial implementation checkpoint: `9666014` (`feat: persist truthful
  recording lifecycle`). The focused Phase 3 suite became green with truthful
  `starting` → `recording` → terminal transitions, recovery, preflight, and
  transcription eligibility.
- Adversarial hardening checkpoint: `9b8dc39` (`test: add adversarial lifecycle
  persistence regressions`) deliberately returned the suite to RED. It exposed
  that a recorder could be invoked before its concrete audio destination had
  been created and verified as private, and added failure-of-failure and
  terminal-immutability contracts.
- Hardening implementation checkpoint: `8c9486d` (`fix: secure recording
  evidence before capture`). Audio destinations are now created and verified
  at `0600` before recorder APIs run, real recorders re-secure their opened
  files, and first-sample timestamps are published only after a successful
  write.
- Refactor checkpoint: `354b91f` (`refactor: isolate lifecycle filesystem
  primitives`). The final atomic-replacement primitive was moved behind the
  existing private-filesystem boundary so the Phase 2 command-launch detector
  remains both conservative and green.

## Verification results

- Focused Phase 3 tests: **11 tests in 2 suites passed**.
- Full Swift regression suite: **35 tests in 8 suites passed**.
- Coverage-instrumented full suite: **35 tests in 8 suites passed**.
- Ruby stop/security regression suite, default and POSIX locales: **13 runs,
  105 assertions, 0 failures** in each locale.
- Ruby architecture suite under an explicit UTF-8 locale: **11 runs,
  59 assertions, 0 failures**.
- Architecture schema/link validator under an explicit UTF-8 locale: pass.
- Retired-hook/command-interpreter validator, default and POSIX locales: pass.
- Swift parser check for every changed production and test source: pass.
- Whitespace/error-marker check across the phase range: pass.
- Gitleaks: no findings in the Phase 3 implementation range or the
  then-current full history.
- Dependency manifests are unchanged; this phase introduces no third-party
  package or dependency-audit delta.

The local Swift toolchain is Swift 6.3 paired with the Command Line Tools 15.4
SDK. Test execution therefore used ignored, temporary compatibility copies of
Swift Testing/support frameworks and the ArgumentParser checkout. These host
accommodations are outside the Git diff. The compiler's repeated
`no unsafe operations occur within 'unsafe' expression` diagnostics originate
inside generated Swift Testing macros on this mismatched host, not in Quill
source.

## Coverage and known gaps

The three Phase 3 lifecycle core files have **80.62% combined line coverage**:

| File | Line coverage |
|---|---:|
| `SessionLifecycle.swift` | 92.54% |
| `RecordingRootPreflight.swift` | 82.72% |
| `RecordingSession.swift` | 72.44% |

The lower `RecordingSession` number is concentrated in production-only
recorder wiring and error presentation that deterministic tests replace at the
injected boundary. Modified application, Core Audio, and transcription
integration files are included in the passing full regression suite but are
not represented as unit-coverage successes; their live platform paths require
the packaged-app gates below.

Live TCC prompts, real Core Audio timing, callback ownership, ring-buffer
saturation, TSan, sandbox bookmarks, low-capacity devices, and real iCloud or
File Provider volumes are not claimed by deterministic Phase 3 tests. CI on
the pinned repository environment and packaged-app/device verification remain
pending until the local branch is authorized for publishing. Callback
ownership, synchronized fallback, and deeper recorder health behavior remain
assigned to Phase 4; bookmarks/remapping and the general v2 store remain later
ordered changes.
