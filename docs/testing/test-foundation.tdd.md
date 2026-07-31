# `test-foundation` TDD evidence

Date: 2026-07-31
Status: **Implementation green; clean-checkout verification pending**

## Source and scope

This change implements the `test-foundation` step in the
[ordered change plan](../architecture/quill-v2-architecture.md#ordered-change-plan)
under the repository's [RED → GREEN rules](../architecture/governing-rules.md#change-and-verification-rules).
The session handoff was supplied separately as `quill-phase-1-handoff.md`.

The tests intentionally exclude live TCC, Core Audio, FluidAudio model
downloads, model accuracy, and a real user Inbox. No externally observable
runtime behavior is changed.

## User journeys

- As a Quill user with a legacy session, I want metadata without track offsets
  to remain readable so that older recordings can still be transcribed.
- As a Quill user, I want transcript JSON, readable Markdown, and clocks to
  retain their current forms while the code gains a test foundation.
- As a CLI user, I want `--out`, configured, and default recording roots to
  retain their documented precedence.
- As a recording user, I want elapsed time to retain its current minute/hour
  display at boundary values.
- As a maintainer, I want every push and pull request to run the package tests
  on the declared macOS and Xcode toolchain, with any terminated command
  failing the job.

## RED → GREEN report

### RED

- Checkpoint: `8bcc62b test: add failing test-foundation coverage`
- Command: `swift test` with local Command Line Tools framework/cache flags
  documented below.
- Result: the executable and dependencies compiled, then the test target
  failed for the intended reasons: `SessionMeta` and `Transcript` were
  file-private, `AppController.format` was private, and the injectable
  root-precedence overload did not exist.

### GREEN

- Checkpoint: `abf2faf refactor: expose pure seams for package tests`
- Command: `swift test` with the same local-only toolchain flags.
- Result: **10 tests in 4 suites passed**.
- Guarantee: the tested legacy transformations and value boundaries retain
  their pre-Phase-1 behavior.

The local host has Command Line Tools rather than full Xcode. Its Swift
Testing framework is installed outside the search/rpath locations inferred by
SwiftPM, and its user cache paths are sandbox-restricted. Local evidence used
equivalent `-F`/`-rpath`, module-cache, and `--disable-sandbox` flags to make
that host installation runnable. Those flags are not product or CI settings.
The CI image provides full Xcode 16.4 and runs the required plain `swift test`.

## Test specification

| # | What is guaranteed | Test file | Type | Result |
|---|---|---|---|---|
| 1 | CLI root overrides configured and default roots | `ConfigTests.swift` | unit | PASS |
| 2 | Configured root overrides the default when no CLI root exists | `ConfigTests.swift` | unit | PASS |
| 3 | Default root and CLI tilde expansion retain legacy behavior | `ConfigTests.swift` | unit | PASS |
| 4 | Two-track v1 metadata preserves file, speaker, order, and offsets | `SessionMetaTests.swift` | compatibility unit | PASS |
| 5 | v1 metadata without offsets defaults both tracks to zero | `SessionMetaTests.swift` | compatibility unit | PASS |
| 6 | Malformed metadata keeps the failing file path in its typed error | `SessionMetaTests.swift` | negative unit | PASS |
| 7 | Transcript JSON round-trips its existing canonical values | `TranscriptTests.swift` | serialization unit | PASS |
| 8 | Transcript Markdown renders minute and hour clocks exactly | `TranscriptTests.swift` | rendering unit | PASS |
| 9 | Elapsed display preserves subhour and hour boundary formats | `ElapsedTimeFormattingTests.swift` | unit | PASS |
| 10 | Pushes and pull requests invoke `swift test` directly on macOS 15 with Xcode 16.4 | `.github/workflows/test.yml` | CI contract | PENDING FIRST RUN |

## Production-source access changes

Each change exists solely to support `@testable` access or deterministic
inputs; none changes the executable's public API or runtime outputs.

| Source | Change | Reason |
|---|---|---|
| `Config.swift` | Added an internal pure overload; existing resolver delegates with the same values | Test precedence without reading or changing a real home-directory config |
| `Quill.swift` | Changed `AppController.format` from `private` to `internal` | Test the existing elapsed clock directly |
| `TranscriptionCoordinator.swift` | Changed `SessionMeta` from file-private to internal | Exercise the v1 compatibility reader |
| `TranscriptionCoordinator.swift` | Changed `Transcript` from file-private to internal | Exercise Codable output and Markdown rendering through `write(to:)` |

## Coverage and known gaps

The new suite covers the selected pure seams and their named boundary/error
cases. Whole-executable line coverage is intentionally not used as a Phase 1
gate: capture, TCC, AppKit control, model loading, and live filesystem behavior
cannot be honestly covered by these isolated tests. Their required fixtures
and integration targets remain assigned to later architecture phases.

The CI workflow does not claim to prove microphone/system capture, sandbox
behavior, model provisioning or accuracy, remapping, signing, notarization, or
real-user Inbox safety.

## Clean-checkout evidence

Pending after the CI/evidence commit. The final record will identify the exact
commit, clean-clone command, architecture validation, and test result.
