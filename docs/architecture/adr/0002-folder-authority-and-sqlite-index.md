# ADR 0002: Session folders own evidence and overlays

Status: **Proposed**
Date: 2026-07-29

## Context

Existing Quill sessions are readable folders. Reporters already organize work
in Finder hierarchies such as `Stories/<story>/Interviews/LASTNAME_date` and
expect an interview folder to remain useful beside every other story asset.
The product needs annotations, corrections, speaker labels, missing-location
handling, remapping, and migration. Putting those values in SQLite makes
querying easy but makes the folder look complete after the user's authored
work is lost. Making SQLite projects the organizational authority would also
compete with the reporter's real folder system.

Today `meta.json` is written only on clean stop, non-atomically, with errors
discarded. Pending transcription scans require that file. A process crash can
therefore leave readable CAF evidence that the application never discovers.

## Decision

Use one authority per datum:

- portable session folders own audio, manifests, transcript generations,
  interview details, part relationships, annotations, corrections, review
  history, and session-local speaker labels;
- the Finder location and parent hierarchy own organization;
- SQLite indexes/caches session content but is never a second writer for
  canonical transcript or annotation bodies;
- presentation and playback artifacts are derived.

Version 1.0 has no app-owned virtual project catalog. SQLite remembers
bookmarks, last-known paths, path facets, availability, fingerprints,
rebuildable search metadata, migration state, and durable job leases. A future
cross-session subject/shared-dictionary feature requires its own authority and
portability decision.

Sidecar writes use schema validation, expected-revision compare-and-swap,
coordinated temporary writes, atomic replacement, and preservation of the
previous valid revision until commit succeeds.

The second writer is not another actor inside the composed application; those
writes are serialized. It is another Quill process/version opened against the
same portable folder, or an external tool manually replacing a documented
sidecar. Before every mutation Quill rereads the on-disk revision. A mismatch
preserves both inputs and requires resolution. File-provider locations remain
read-only in 1.0, so conflict handling is not permission to weaken the Inbox
privacy rule.

`session.json` is capture-only. It owns lifecycle, initial requested tracks,
trusted per-track failure observations, and terminal capture result. Once the
live process writes `complete` or `failed`, or recovery writes `interrupted`,
the file is immutable. Revisioned `state.json` owns interview details, ordered
part links, transcript-generation references, and the active transcript
pointer. Added imports get immutable `parts/<part-id>.json` manifests.
`annotations.json` remains the revisioned overlay.

Legacy adoption creates `session.json` and references existing artifacts. It
does not rewrite `meta.json` or `transcript.json`.

For every new recording, session persistence precedes capture:

1. create a `0700` session directory;
2. atomically write `session.json` with state `starting`, capture profile,
   initial part, and per-track criticality;
3. atomically write `state.json` revision 0 with the initial capture-part
   reference and any optional details;
4. start every requested recorder pipeline;
5. within a provisional three-second transition deadline, atomically
   transition to `recording` after at least one requested track delivers a
   first accepted buffer and every other requested track is live or has a
   typed failure; a timed-out track gets `start_timeout` and fallback before
   proceeding; write `failed` only if no requested track becomes live;
6. the live process atomically transitions to `complete` or observed `failed`;
7. a later startup scan transitions a remaining non-terminal manifest to
   inferred `interrupted`.

Startup discovery scans manifests in every non-terminal state. It does not use
the existence of clean-stop metadata as proof that a session exists.

Lifecycle `complete` means Quill finalized the evidence it captured; it does
not claim every requested track was healthy. Per-track status and transcript
completeness express degradation without discarding a healthy primary source.
Recorder API success is not liveness. Liveness requires the first buffer to
reach the bounded handoff/writer and establish first-sample time. No pipeline
may hold the manifest in `starting` while another writes unbounded audio.
Track failures written by the live process before a later crash survive
unchanged when recovery transitions the session to `interrupted`;
session-level `failure` remains null because recovery did not observe the
process-ending cause.

`failed` always includes a typed payload written by the process that observed
the error. `interrupted` has no trusted failure payload because recovery only
knows that no terminal transition was written. If an observed failure cannot
be persisted, the next launch correctly classifies it as `interrupted`.

Live recording and imported-media adoption initially stage into a secured
local APFS Inbox, defaulting to `~/Quill` after an `NSOpenPanel` grant. Before
creating a session, Quill proves that the Inbox volume supports and preserves
`0700`
directories, `0600` files, same-directory atomic rename, file/directory
synchronization, and the recording capacity reserve. A failed capability
preflight names the detected filesystem and refuses recording before evidence
is created.

The preflight separately proves that the path is not an iCloud ubiquitous
item, File Provider domain, or Desktop/Documents location managed by iCloud
Desktop & Documents. This is a privacy/egress capability, not a proxy for APFS
atomicity: a path can pass every filesystem operation and still be rejected
because another service may upload or evict interview data.

Sidecar atomicity is claimed only on a preflighted supported root: write and
synchronize a temporary sibling, rename within the same filesystem, then
synchronize the parent directory. Quill makes no atomic-write guarantee for
SMB, NFS, cloud-file providers, exFAT, or FAT32.

Unsupported roots remain available for import/export. Imported media is copied
into the Inbox before editing or transcription state is persisted. Google
Drive is an explicit export destination, not a canonical session root.

After finalization, the reporter may move or rename the whole interview folder
under any supported local story hierarchy. Quill refreshes bookmarks where
possible. Otherwise it offers locate/remap for one interview or a moved parent
hierarchy. A location under a never-granted parent requires a fresh
`NSOpenPanel` grant and app-scoped security bookmark; remapping is not a
database repair. Missing never means deleted.

One interview folder may contain multiple explicit sequential parts. Tracks in
a part are simultaneous. Each imported file begins as a separate processing
item; combining parts requires user-selected order and leaves visible part
boundaries. Related interviews remain separate. Unknown supporting files in
or beside the interview folder are ignored and preserved.

## Consequences

- A session remains useful and carries its notes when moved or backed up.
- Corrupt SQLite can be quarantined and its session index rebuilt.
- Finder remains the reporter's organization system; Quill does not create a
  competing hierarchy.
- Read-only referenced sessions cannot accept session-local edits. Import is
  copy-by-default into a writable managed root; read-only reference mode is
  visibly read-only.
- exFAT/FAT/network roots are visibly unsupported for live recording rather
  than silently weakening permission or atomicity guarantees.
- Sidecar conflicts, copied folders, and unsupported versions require explicit
  UX rather than last-writer-wins.
- A crash at any capture lifecycle boundary leaves a discoverable manifest.
- Combining media never hides its original files or part boundaries.

## Alternatives rejected

### SQLite owns all mutable metadata

Rejected because annotation and label loss would be invisible when portable
session folders still existed. Backup/export would become a prerequisite for
the first annotation.

### Sidecars own the complete library hierarchy

Rejected because one sidecar cannot authoritatively represent an external
Finder hierarchy spanning folders and volumes. Search/index state remains
derived operational data.

### Dual-write sidecars and SQLite

Rejected because two canonical writers guarantee ambiguity after a partial
failure. SQLite may cache sidecar content only with the indexed sidecar
revision and must accept the sidecar as authority.

## Verification

- Removing/rebuilding SQLite preserves session annotations and labels.
- Moving a folder preserves its `sessionID` and authored overlays.
- Moving a parent story folder can be remapped once without re-creating each
  interview.
- A write crash leaves either the old or new valid sidecar, never partial JSON.
- Revision conflicts retain both inputs and require resolution.
- Legacy adoption is idempotent and byte-for-byte preserves legacy evidence.
- Corrupt or deleted SQLite does not erase Finder organization or interview
  details.
- Failure injection between every lifecycle transition discovers the session
  and never promotes it to `complete`.
- A manifest write error prevents recording start and preserves the specific
  filesystem error.
- local APFS preflight passes; exFAT and network-volume fixtures fail before
  manifest creation with filesystem/capability-specific errors.
- iCloud-managed Documents and File Provider fixtures fail the privacy/egress
  capability even when APFS permission/rename/synchronization probes pass.
- Explicitly ordered imported parts retain their original files and visible
  boundaries after quit/reopen.
