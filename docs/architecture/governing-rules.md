# Quill governing engineering rules

Status: **Proposed for Phase 0 acceptance**
Date: 2026-07-31

These rules apply to every Quill change after the architecture baseline. They
turn the product and privacy decisions into reviewable implementation
constraints. A change that cannot produce the evidence named here is not ready
to merge.

## Product and evidence rules

1. **Audio is the source of truth.** Capture files are preserved and playable;
   transcript text is an evidence view over those files.
2. **Corrections are overlays.** User corrections may become the default
   display and copy projection, but the machine transcript, original anchors,
   correction history, and audio remain inspectable.
3. **Uncertainty is visible.** Low confidence, unclear language, uncertain
   speakers, partial evidence, and transcription failures become explicit
   `Needs Human Intervention` items. They are never silently normalized away.
4. **Identity is confirmed, not inferred.** A diarization cluster or capture
   profile may suggest a label, but Quill must not make an unverified claim
   about a person's identity.
5. **Literal copy is the default.** Punctuation cleanup, filler removal,
   redaction, grammar changes, and other editorial transformations require a
   distinct user-correction state.

## Authority and storage rules

1. **One datum has one canonical writer.** Interview folders own evidence,
   transcript generations, details, parts, annotations, corrections, review
   history, and session-local speaker labels.
2. **Finder owns organization.** Quill must not create a competing virtual
   project hierarchy in 1.0. SQLite is a rebuildable index/cache and owns
   operational job state only.
3. **Terminal capture history is immutable.** `session.json` is written for
   lifecycle recovery and becomes byte-immutable at terminal state. Mutable
   details, part links, transcript pointers, and overlays use revisioned
   sidecars with compare-and-swap semantics.
4. **Evidence writes are non-destructive.** Atomic replacement, schema
   validation, revision checks, and preservation of the previous valid
   revision are required for sidecar mutation.
5. **Remapping is explicit.** A moved folder may be rediscovered or remapped,
   but Quill must never silently rewrite, delete, or duplicate folder-owned
   evidence.

## Privacy and platform rules

1. **Local by default means local by enforcement.** Meeting-derived bytes do
   not leave the Mac except through an explicit user export or diagnostic
   handoff that the user inspects and initiates.
2. **The Inbox must be non-synced.** `~/Quill` is the default proposal. iCloud
   Desktop/Documents and File Provider locations are rejected independently of
   APFS and atomicity capability checks.
3. **No hidden persistence paths.** Do not write interview data, full paths,
   transcript text, or source identities to predictable temporary locations or
   automatic crash uploaders.
4. **Permissions are honest.** A denied or revoked permission disables only
   incompatible capture profiles and explains the recovery path. TCC state is
   never manipulated directly.
5. **The signed app is the release boundary.** No production release is
   distributed as an upgrade between the legacy executable and the signed
   application unless a separate security decision explicitly authorizes it.

## Scope rules

1. Version 1.0 is limited to recording, imported media, local transcription,
   playback, folder remapping, speaker naming, Needs Human Intervention, and
   non-destructive corrections.
2. Meeting bots, participant announcements, cloud accounts/synchronization,
   coaching, sentiment/talk-time scoring, promotional feature prompts, and
   unverified source identity claims are excluded.
3. Hot Quote, Fact Check, comments, global search, shared dictionaries,
   formatted exports, Google Drive, and calendar assistance require their own
   reviewed change after the 1.0 evidence path works.

## Change and verification rules

1. **Use stable slugs.** Each change has one branch, one intent, and one slug;
   do not use speculative pull-request numbers as architectural references.
2. **RED → GREEN.** A production change begins with a failing test, fixture, or
   reproducible manual check. Implementation is not evidence until that check
   passes.
3. **Test targets follow production modules.** No new production module may
   land without a runnable corresponding test target, except documentation or
   packaging-only changes.
4. **Typed failures cross boundaries.** Friendly UI copy may simplify wording,
   but it must not collapse distinct recovery paths into a generic error.
5. **Measure before committing to expensive paths.** Model provisioning,
   accuracy, App Sandbox/Core Audio capture, and distribution size are release
   gates, not assumptions.
6. **User walkthroughs are evidence.** The packaged app must be walked by both
   target reporters before the 1.0 path is declared complete; a mocked UI does
   not prove TCC, capture, playback, model, or remapping behavior.
