# `lifecycle-recovery-integrity` TDD evidence

Date: 2026-08-03
Status: **Local GREEN; pinned CI pending an authorized push**

## Scope

This remediation closes Phase 3 findings F4–F7. It bounds recorder startup
while a synchronous start is in flight, keeps AppKit's main actor responsive,
allows safe interrupted evidence to enter transcription discovery, and
isolates recovery failures per session directory.

The work deliberately leaves recorder callback ownership, ring buffers,
synchronized fallback internals, capture URL identity, and frame-derived
duration to their assigned later phases.

## RED → GREEN

- Runtime RED `c299f04` (`test: expose lifecycle recovery integrity failures`)
  completed with **5 intended issues**. It reproduced a blocking recorder start
  exceeding its deadline, an oldest corrupt manifest aborting the batch, a
  future manifest being rewritten, and interrupted evidence being excluded
  from transcription.
- Compile-time RED `bc16019` (`test: require responsive recovery discovery
  boundaries`) reached the intended missing controller and coordinator seams
  needed to test main-actor responsiveness and the real resume-discovery path.
- GREEN `d1683a1` (`fix: preserve recovery integrity and responsiveness`)
  passed the focused lifecycle and transcription-recovery run with **17 tests
  in 2 suites**.

## Result

- Recorder starts launch concurrently beneath one monotonic deadline. A late
  success is stopped, and an unresolved attempt receives typed
  `start_timeout` without waiting for the blocking call to return.
- `RecordingSessionController` owns the synchronous session graph on an actor,
  so preflight, permission prompts, recorder starts, and liveness polling do
  not run on the main actor.
- Recovery returns recovered directories plus typed per-directory failures and
  continues after inspection, decode, unsupported-version, or persistence
  errors.
- Unsupported schema versions are loud and byte-immutable.
- An interrupted session is transcription-eligible only when at least one safe
  relative, non-symlink, nonempty regular media track survives validation.
- Real `resumePending` discovery keys v2 sessions on `session.json`; it no
  longer depends on clean-stop-only `meta.json`.

Pinned macOS 15 / Xcode 16.4 CI has not run for this unpushed branch.
