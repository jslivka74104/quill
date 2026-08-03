# `lifecycle-truthfulness` TDD evidence

Date: 2026-08-03
Status: **Local GREEN; pinned CI pending an authorized push**

## Scope

This remediation closes Phase 3 findings F1–F3. It makes track lifecycle data
decidable at every transition, resolves non-terminal tracks before a session
becomes terminal, and gives recovery-authored interrupted tracks a typed
failure. It does not change recorder callback ownership, frame-derived
duration, capture URL identity, launch logging, or model provisioning.

## RED → GREEN

- Runtime RED `cbf3f36` (`test: expose lifecycle track truthfulness failures`)
  added status/failure pairing, terminal-state, failure-code, start-offset,
  duration, and byte-count assertions. The focused run completed and reported
  **22 intended issues**, including terminal tracks left `recording`, missing
  recovery failures, truncated offsets, and absent byte counts.
- Compile-time RED `14e6ae2` (`test: require terminal evidence validation
  failures`) reached the intended missing injectable file-attributes boundary.
  It added coverage for both finalization-failure call sites: a throwing
  recorder stop with valid media and an evidence-attributes failure.
- GREEN `f00f623` (`fix: enforce truthful terminal track states`) passed the
  focused lifecycle run with **12 tests**.

## Result

- A terminal manifest cannot retain a `pending` or `recording` track.
- `pending`, `recording`, and `complete` tracks have no failure; `degraded`,
  `interrupted`, `missing`, and `invalid` tracks carry a typed failure.
- Finalization failure preserves valid media as `complete` with its real byte
  count and marks unvalidated media `invalid` with
  `track_evidence_validation_failed`.
- Recovery-authored interrupted tracks use
  `process_terminated_unexpectedly` without inventing a session-level cause.
- Start offsets round to the nearest millisecond; the exercised 25 ms fixture
  remains 25 rather than truncating.

Pinned macOS 15 / Xcode 16.4 CI has not run for this unpushed branch.
