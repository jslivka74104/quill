# ADR 0003: Version transcripts and scope identity explicitly

Status: **Proposed**
Date: 2026-07-29

## Context

The current transcript persists timed segments but discards FluidAudio's word
timing. It labels tracks as `me` and `them`, has no stable session identity,
and cannot distinguish a diarization cluster from a real human. Word seek,
non-destructive correction, duplicate handling, and trustworthy speaker names
need stable but correctly scoped identifiers.

Voice processing is default-off and can fall back to raw microphone capture.
When meetings play through speakers, the far end may therefore appear in both
the system and mic tracks. Because promoted transcripts are immutable, echo
classification must be represented in v2 rather than hidden later in a
renderer.

Product discovery also established that a microphone is not an identity
boundary. In the phone-speaker and in-person profiles, one microphone track
contains the reporter and one or more sources. In an online meeting, system
audio is primary evidence and microphone audio is secondary; failure of the
secondary track must not make healthy source audio unusable. A phone routed
through Continuity, FaceTime Audio, or another Mac bridge uses a separate
`phone_via_mac` profile so clean system audio is not discarded.

## Decision

Introduce:

- a UUID `sessionID` in `session.json`;
- a persisted capture profile, ordered parts, and per-track criticality;
- a content fingerprint for canonical evidence;
- an immutable UUID `transcriptID` per transcript generation;
- stable word IDs and integer session-timeline millisecond bounds;
- a `trackID` and optional session-local `speakerClusterID` on every word;
- model/version/hash/settings provenance on every promoted transcript;
- a required presentation disposition on every word;
- non-destructive `suppressed_echo` metadata containing the different matched
  track/range, method, confidence, and therefore echo direction;
- user-confirmed speaker display names in `annotations.json`, never in
  transcript evidence;
- corrected reading text, original anchors/quotes, edit category, author, and
  history in `annotations.json`, never as transcript mutation;
- durable human-review items with open/resolved history;
- both transcript-word anchors and timeline anchors that can exist before
  transcription;
- user-authored echo-disposition overrides with independent
  `dispositionOverrideID` values in `annotations.json`;
- no cross-session `personID` or voice embeddings in the first architecture.

Presentation blocks reference word ranges and are not a second source of text.
Re-transcription creates a new generation. Annotation re-anchoring across
generations is explicit and preserves the old anchor and method.

Capture profiles supply only defensible speaker priors. Online-meeting
microphone audio may use a `self` prior after capture/echo validation;
phone-speaker, in-person, and imported mixed tracks are diarized without
assuming a speaker count or identity. `phone_via_mac` uses the same two-track
identity caution as an online meeting.

A transcript can become active and visibly `partial` when all primary tracks
were processed but a secondary track failed. A failed primary track prevents a
complete presentation but does not delete readable partial output. Sequential
parts retain explicit boundaries.

## Consequences

- Word-click playback has a stable session timeline.
- Diarization can improve without rewriting user-confirmed names.
- A speaker cluster never silently becomes a claim about a person.
- A phone-speaker microphone can represent two or more session-local clusters.
- Automatic echo suppression can improve reading without deleting source
  evidence; false positives can be restored through an overlay.
- The schema can represent either echo direction even though the first
  suppressor emits only mic-source/system-match decisions.
- Transcript generations and annotation anchors require migration/re-anchoring
  UX rather than in-place mutation.
- User corrections become the normal reading/search/copy projection while the
  machine original and audio remain inspectable and revertible.
- UUIDs alone do not solve duplicate imports; evidence fingerprints and
  explicit conflict rules remain necessary.

## Alternatives rejected

### Use display names directly on words/segments

Rejected because a mutable or uncertain identity would rewrite transcript
evidence and could be presented as confirmed.

### Use one global speaker/person ID

Rejected because diarization clusters are session-local hypotheses. Global
voice identity adds consent, false-match, retention, and deletion obligations
that are outside the reliable manual-labeling milestone.

### Keep segment timing only

Rejected because word seek and durable annotation anchors would require
heuristics over text that changes across transcript generations.

### Suppress echo only in presentation

Rejected because the promoted transcript would omit the decision, method, and
confidence that explain why captured words disappeared. Different renderers
could also disagree.

## Verification

- v2 fixtures preserve every word's bounds, track, cluster, and provenance.
- IDs and cross-references satisfy documented invariants.
- user labels can change without changing transcript bytes.
- every textual edit is marked “Corrected by user,” including punctuation,
  grammar, filler removal, and redaction;
- resolved uncertainty leaves review history without remaining in the active
  `Needs Human Intervention` queue;
- online, phone-speaker, phone-via-Mac, in-person, and imported fixtures enforce their
  profile-specific speaker priors and primary/secondary rules;
- a failed online-meeting mic can yield a visibly partial active transcript
  from healthy system audio; a failed primary source cannot look complete;
- sequential imports retain part boundaries;
- re-transcription leaves the prior generation and anchors intact.
- echo fixtures cover aligned duplicates, double-talk, unique mic words,
  threshold boundaries, and user restoration of a false positive.
- held-out false suppression of unique source words is below 1%, with zero
  false suppression in hand-authored unique-speech and double-talk safety
  fixtures; residual echo is accepted as the safer failure.
- suppressed words remain in transcript evidence and evidence-mode rendering.
- an uncertain meeting-name candidate is visibly suggested and cannot become
  confirmed without a user action.
- duplicate/conflict fixtures distinguish session, location, evidence,
  transcript, cluster, and future person identity.
