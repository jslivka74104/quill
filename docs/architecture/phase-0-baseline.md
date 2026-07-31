# Phase 0: Architecture baseline

Status: **Accepted — Phase 0 complete**
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
- [x] ADRs 0001–0004 were accepted by the project owner on 2026-07-31; ADR
      0004 retains its explicit measurement block before production use.
- [x] Full-size model and signed App Sandbox/Core Audio measurements are
      deferred to the foundation boundary before their dependent production
      changes; they do not deadlock the Phase 0 documentation gate.
- [x] The package was committed atomically from a clean checkout in `42a86ff`.

## Validation commands

Run these from the repository root:

```sh
ruby scripts/test-architecture.rb
ruby scripts/validate-architecture.rb
```

The contract tests adversarially remove named package members, check the
pre-terminal lifecycle and speaker-label history shapes, and verify CI
enforcement. The validator requires the exact four ADRs and five schemas,
parses every schema, verifies cross-file `$ref` targets and local Markdown
links, and rejects speculative PR references. Broader schema cross-file
invariants and product fixtures belong to `contracts-v2`; they must not be
claimed as implemented by this documentation-only phase.

## Phase 0 exit gate

Phase 0 is complete: the project owner accepted ADRs 0001–0004 on 2026-07-31,
and both validation commands pass from a clean checkout. The documentation
package and `test-foundation` landed before owner acceptance because they add
contracts and verification without implementing v2 product behavior. Phase 2
may begin only after the remediation branch also passes its pinned CI lane.

The full-size model and signed App Sandbox/Core Audio feasibility work is
deferred to the foundation boundary in the ordered change plan. Those remain
hard gates before `contracts-v2` and their dependent production paths, not
prerequisites that make the Phase 0 documentation gate impossible to close.
