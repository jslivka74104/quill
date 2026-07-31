# `test-foundation` TDD evidence

Date: 2026-07-31
Status: **Local and pinned Xcode 16.4 CI tests green**

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
  reached an intentional compile-time RED because the characterization seams
  did not yet exist: `SessionMeta` and `Transcript` were file-private,
  `AppController.format` was private, and the injectable root-precedence
  overload was absent. This checkpoint proves scaffold/API absence, not a
  behavioral regression.

### GREEN

- Checkpoint: `abf2faf refactor: expose pure seams for package tests`
- Command: `swift test` with the same local-only toolchain flags.
- Result: **10 tests in 4 suites passed**.
- Guarantee: the tested legacy transformations and value boundaries retain
  their pre-Phase-1 behavior.

### Diff-review regression cycle

- RED checkpoint: `e614739 test: preserve lazy CLI root precedence`.
- RED result: the new test proved the first helper refactor evaluated the
  configured-root expression even when a CLI override was present.
- GREEN checkpoint: `397104a fix: keep CLI root resolution lazy`.
- GREEN result: the helper accepts a lazy configured-root input, all **11
  tests in 4 suites passed**, and CLI precedence again short-circuits before
  config loading exactly as it did before Phase 1.

### Pinned-toolchain compatibility RED → GREEN

- Remote run: `30646589442` at commit `9859b2d`.
- Command: plain `swift test` on macOS 15 with Xcode 16.4 / Swift 6.1.2.
- RED result: compilation stopped before tests because Xcode 16.4's SDK does
  not mark `AVAudioFormat` as `Sendable`, while Swift 6 requires associated
  values of `Error` types to be sendable.
- Diagnostic: `RecorderError.formatUnsupported(AVAudioFormat)` has a
  non-sendable associated value in `MicRecorder.swift:19`.
- Regression seam: this is an SDK/compiler-import compatibility failure, so
  the pinned CI compile is the correct end-to-end check. The newer local SDK
  marks the immutable `AVAudioFormat` class `NS_SWIFT_SENDABLE` and therefore
  cannot reproduce the older imported declaration in a source-level unit
  test.
- Fix: `d34f291 fix: support Xcode 16.4 AVAudioFormat imports` marks only the
  `AVFoundation` import in `MicRecorder.swift` as `@preconcurrency`, preserving
  the typed error and recorder behavior while accepting the older SDK's
  missing annotation.
- GREEN run: `30647885418` used Xcode 16.4 / Swift 6.1.2, completed a clean
  build in 70.99 seconds, and passed all **11 tests**.

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
| 2 | CLI root short-circuits without evaluating configured-root loading | `ConfigTests.swift` | regression unit | PASS |
| 3 | Configured root overrides the default when no CLI root exists | `ConfigTests.swift` | unit | PASS |
| 4 | Default root and CLI tilde expansion retain legacy behavior | `ConfigTests.swift` | unit | PASS |
| 5 | Two-track v1 metadata preserves file, speaker, order, and offsets | `SessionMetaTests.swift` | compatibility unit | PASS |
| 6 | v1 metadata without offsets defaults both tracks to zero | `SessionMetaTests.swift` | compatibility unit | PASS |
| 7 | Malformed metadata keeps the failing file path in its typed error | `SessionMetaTests.swift` | negative unit | PASS |
| 8 | Transcript JSON round-trips its existing canonical values | `TranscriptTests.swift` | serialization unit | PASS |
| 9 | Transcript Markdown renders minute and hour clocks exactly | `TranscriptTests.swift` | rendering unit | PASS |
| 10 | Elapsed display preserves subhour and hour boundary formats | `ElapsedTimeFormattingTests.swift` | unit | PASS |
| 11 | Pushes and pull requests invoke `swift test` directly on macOS 15 with Xcode 16.4 | `.github/workflows/test.yml` | CI contract | PASS |

## Production-source access changes

Each change exists solely to support `@testable` access or deterministic
inputs; none changes the executable's public API or runtime outputs.

| Source | Change | Reason |
|---|---|---|
| `Config.swift` | Added an internal lazy-input overload; existing resolver delegates with the same values | Test precedence without reading or changing a real home-directory config, while preserving CLI short-circuiting |
| `Quill.swift` | Changed `AppController.format` from `private` to `internal` | Test the existing elapsed clock directly |
| `TranscriptionCoordinator.swift` | Changed `SessionMeta` from file-private to internal | Exercise the v1 compatibility reader |
| `TranscriptionCoordinator.swift` | Changed `Transcript` from file-private to internal | Exercise Codable output and Markdown rendering through `write(to:)` |

## Coverage and known gaps

The new suite covers the selected pure seams and their named boundary/error
cases. `swift test --enable-code-coverage` followed by `llvm-cov report`
measured 68 of 1,264 executable-source lines, or **5.38% whole-executable line
coverage**. That repository-wide number is intentionally not used as a Phase
1 gate: capture, TCC, AppKit control, model loading, and live filesystem
behavior cannot be honestly covered by these isolated tests. Their required
fixtures and integration targets remain assigned to later architecture
phases.

The CI workflow does not claim to prove microphone/system capture, sandbox
behavior, model provisioning or accuracy, remapping, signing, notarization, or
real-user Inbox safety.

## Clean-checkout evidence

- Commit checked: `397104a fix: keep CLI root resolution lazy`
- Checkout: `git clone --no-local` into
  `/private/tmp/quill-test-foundation-final.gEjVqQ/quill`; the clone contained no
  inherited `.build` directory.
- Test: local-toolchain equivalent of `swift test` completed a full dependency
  resolution and clean build in 81.68 seconds, then **11 tests in 4 suites
  passed**.
- Architecture: `ruby scripts/validate-architecture.rb` passed all five schema,
  local reference, local link, and speculative-reference checks.
- Cleanliness: `git status --short --branch` reported
  `## master...origin/master` with no modified or untracked files.

That clean-checkout record predates the push that created remote evidence.
Subsequent GitHub Actions runs `30647885418` at `d34f291` and `30648034509` at
`a458158` both passed the pinned Xcode 16.4 lane. The latter is the final Phase
1 commit before foundation remediation.
