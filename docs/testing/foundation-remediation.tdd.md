# Foundation remediation TDD evidence

Date: 2026-07-31
Status: **Architecture GREEN; project-owner acceptance and pinned Swift CI pending**

## Source and scope

This remediation addresses the adversarial review of Phase 0 and Phase 1. It
changes architecture contracts and their enforcement, exposes the existing
Parakeet grouping seam to package tests, and corrects the historical evidence
record. It does not begin the Phase 2 `remove-on-stop` production change.

## User journeys

- As a capture maintainer, I need a truthful pre-terminal manifest so recovery
  never depends on fabricated timestamps, offsets, or terminal track states.
- As a reporter, I need speaker confirmations and renames to retain inspectable
  history rather than overwrite the prior identity decision.
- As a project owner, I need CI to reject a missing or unreviewed normative
  architecture file before later work can cite the baseline.
- As a transcription maintainer, I need Parakeet grouping boundaries preserved
  without loading a model or reading user audio.
- As a reviewer, I need phase and TDD evidence to distinguish recorded facts,
  pending gates, compile-time RED, and runtime RED.

## RED

- Checkpoint: `1093d0d test: add foundation remediation regressions`.
- Command: `ruby scripts/test-architecture.rb`.
- Result: **9 runs, 14 assertions, 8 expected failures, 0 errors**. The failures
  reproduced missing exact-file enforcement, unrepresentable pre-terminal
  fields, absent speaker-label event history, missing CI commands, private
  Parakeet grouping, the phase-gate deadlock, and stale remote-run language.
- A pinned-equivalent local `swift test` attempt did not count as Parakeet RED:
  the host failed first inside `swift-argument-parser` because its Swift 6.3.3
  compiler, Swift 6.3.2 SDK, and macOS 15.4 compatibility SDK disagree about
  `SendableMetatype`. The intended Swift test target was not reached.

## GREEN

- Checkpoint: `81c735f fix: enforce remediated foundation contracts`.
- Command: `ruby scripts/test-architecture.rb`.
- Result: **9 runs, 42 assertions, 0 failures, 0 errors, 0 skips** before the
  additional already-green exact-package/acceptance assertions were added.
- Final local rerun after those assertions: **10 runs, 47 assertions, 0
  failures, 0 errors, 0 skips**.
- Command: `ruby scripts/validate-architecture.rb`.
- Result: all five named schemas parsed; local schema references and Markdown
  links resolved; no speculative pull-request references were found.

## Test specification

| Guarantee | Evidence | Type | Result |
|---|---|---|---|
| The package contains exactly ADRs 0001–0004 and the five named schemas | `ArchitectureContractTest#test_required_architecture_package_is_exact` | contract | PASS |
| Removing a named schema or ADR fails even if its Markdown link is also removed | adversarial temporary-copy tests | negative integration | PASS |
| An unreviewed extra normative schema fails validation | temporary-copy test | negative integration | PASS |
| The session schema permits null pre-start facts plus `pending` and `recording` track states | session-schema shape test | contract | PASS |
| Speaker labels are immutable, identified supersession events | annotations-schema shape test | contract | PASS |
| CI runs architecture tests, package validation, and Swift tests | workflow contract test | contract | PASS |
| Phase 0 defers later feasibility work without permitting Phase 2 before owner acceptance | phase-gate contract test | contract | PASS |
| Historical Phase 1 evidence no longer denies the remote runs it cites | evidence contract test | contract | PASS |
| Parakeet grouping handles empty input, punctuation, the one-second threshold, and the 60-word cap | `ParakeetSegmentationTests.swift` | Swift unit | PENDING PINNED CI |

## Coverage and remaining gates

The Ruby contract suite exercises every remediation concern and both positive
and adversarial validator paths. Repository-wide coverage remains the
historical Phase 1 value until the Swift suite can run on the pinned Xcode 16.4
lane. No Swift PASS or updated percentage is claimed from this host.

Before Phase 2 begins:

1. the project owner must accept or explicitly amend ADRs 0001–0004; and
2. the remediation branch must pass the pinned CI lane, including the four new
   Parakeet tests and both architecture commands.
