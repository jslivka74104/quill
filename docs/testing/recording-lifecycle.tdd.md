# `recording-lifecycle` TDD evidence

Date: 2026-08-02
Status: **RED established; implementation pending**

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

## Planned test specification

| Guarantee | Test target | Evidence status |
|---|---|---|
| Secured directory and atomic `starting` manifest precede recorder start | `RecordingLifecycleTests` ordering test | Pending RED |
| Every root capability fails specifically before evidence creation | `RecordingRootPreflightTests` capability matrix | Pending RED |
| No live requested track produces an observed typed `failed` transition | `RecordingLifecycleTests` start-failure test | Pending RED |
| Recovery alone authors `interrupted` with null session failure | `RecordingLifecycleTests` recovery matrix | Pending RED |
| First-buffer liveness promotes to `recording`; finalization then persists `complete` | `RecordingLifecycleTests` clean-transition test | Pending RED |
| Terminal persistence failure stays observable and recoverable | `RecordingLifecycleTests` terminal-write failure test | Pending RED |
| Injected crashes leave truthful discoverable state at every post-manifest boundary | `RecordingLifecycleTests` crash matrix | Pending RED |
| Real local temporary storage preserves `0700`/`0600` | `RecordingRootPreflightTests` filesystem integration | Pending RED |
| Legacy and Phase 2 behavior remains green | Existing Swift and Ruby suites | Pending GREEN |

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
- Checkpoint: pending the immediate RED commit.

### GREEN

Pending implementation and verification.

## Coverage and known gaps

Pending. Live TCC prompts, real Core Audio timing, callback ownership, ring
buffer saturation, TSan, sandbox bookmarks, and File Provider devices are not
claimed by deterministic Phase 3 tests. They remain explicit later-phase or
packaged-app gates.
