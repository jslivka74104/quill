# Phase 0: Architecture baseline

Status: **In progress**
Started: 2026-07-31

Phase 0 makes the architecture package reviewable and enforceable. It does not
implement product behavior, migrate recordings, or distribute a build.

## Scope

The baseline package consists of:

- `quill-v2-architecture.md`;
- ADRs 0001–0004;
- the five normative JSON Schemas;
- `governing-rules.md`;
- this acceptance checklist.

The package must be reviewed and accepted as one unit. A partial architecture
package is not a valid foundation for implementation.

## Acceptance checklist

- [x] The product contract names the reporter workflow, local-only boundary,
      audio authority, literal copy behavior, and 1.0 scope.
- [x] The authority table has one canonical writer per datum.
- [x] The lifecycle distinguishes `failed` from `interrupted` and defines a
      bounded first-buffer transition.
- [x] Capture profiles distinguish online meetings, phone speaker, phone via
      Mac, in-person, and imported media.
- [x] Session, state, part, transcript, and annotation contracts exist as
      versioned schemas.
- [x] Model provisioning is recorded as a conditional decision pending a
      full-size measurement and local accuracy run.
- [x] The proposed Inbox default is `~/Quill`, with iCloud/File Provider
      rejection called out as a separate capability check.
- [x] User corrections, speaker confirmation, echo disposition overrides, and
      Needs Human Intervention have durable identities and history.
- [x] The ordered change plan uses stable slugs and contains no speculative PR
      references.
- [x] Governing rules are written down in a repository-local document.
- [ ] ADRs 0001–0004 are accepted by the project owner or explicitly amended.
- [ ] The full-size model and signed App Sandbox/Core Audio feasibility gate
      has measured evidence.
- [ ] The package is committed atomically from a clean checkout.

## Validation commands

Run these from the repository root:

```sh
ruby scripts/validate-architecture.rb
```

The validator checks the required package files, parses every schema, verifies
cross-file `$ref` targets and local Markdown links, and rejects speculative PR
references. The schema cross-file invariants and contract fixtures belong to
Phase 1's test foundation and Phase 3's contracts work; they must not be
claimed as implemented by this documentation-only phase.

## Phase 0 exit gate

Phase 0 is complete when the project owner accepts the package, all validation
commands pass from a clean checkout, and the package is committed atomically.
The next change is `test-foundation`; no product implementation should begin
before that gate is recorded.
