# ADR 0004: Choose verified model provisioning

Status: **Accepted — Option C conditionally selected; production use remains measurement-blocked**
Date: 2026-07-29

## Context

The current `ParakeetEngine.prepare()` calls:

```swift
AsrModels.downloadAndLoad(version: .v2)
```

FluidAudio downloads roughly 600 MB of Core ML model content on first use and
stores it in a cache that FluidAudio owns. Quill neither selects immutable
artifact URLs nor verifies an application-controlled hash.

The security objectives are:

1. microphone audio, system audio, transcripts, notes, identities, and
   summaries never leave the Mac except through explicit user export;
2. Quill activates only a model whose bytes and provenance match a
   Quill-owned manifest.

Removing the core app's outgoing-network entitlement is valuable
defense-in-depth and is statically inspectable, but it is not itself either
security objective. Bundling is one implementation option, not a premise.

Model provisioning is also a distribution and update decision. Putting a 600
MB model inside every application build may force large downloads and slow
notarization for app-only updates. That cost must be measured before choosing a
design.

Product discovery established three experience requirements:

- ship a reasonably sized signed DMG rather than bundling the roughly 600 MB
  speech model;
- make a clearly explained first-run model download acceptable;
- allow recording and media import before the model is available, with durable
  transcription later.

## Evaluated options

### Option A: Model bundled inside Quill.app

The signed app contains the model and Quill-owned manifest. The core app has no
outgoing-network entitlement.

Advantages:

- strongest statically inspectable locality boundary;
- simplest first-run state machine;
- one signed/notarized release unit;
- first transcription works offline.

Costs:

- app-only updates may redownload the full model;
- every release signs, uploads, and notarizes the large payload;
- application archive and install size increase substantially.

### Option B: Separate signed model package

An all-in-one installer installs both `Quill.app` and a separately versioned,
signed model payload. Later app-only updates leave an unchanged model in place.
The core app has no outgoing-network entitlement.

Advantages:

- preserves the statically inspectable no-network boundary for the core app;
- avoids repeating an unchanged model in app-only updates;
- first transcription works offline after installation.

Costs:

- adds package ownership, version compatibility, upgrade, rollback, repair, and
  uninstall states;
- requires a Quill-controlled installer/update surface;
- notarization and signature validation span more than one component.

### Option C: Hash-pinned first-use download

The core app downloads from one Quill-allow-listed HTTPS origin, writes to a
private staging location, verifies a Quill-owned SHA-256/manifest, and only
then atomically activates the model. Audio and transcript types never enter the
download client API.

Advantages:

- smallest application and app-only updates;
- simplest path from the current FluidAudio behavior;
- still gives Quill control of model integrity.

Costs:

- the core app retains a broad outgoing-network entitlement that cannot express
  “model downloads only”;
- no-entitlement locality is no longer statically provable;
- first transcription requires a successful download unless preflighted;
- partial downloads, redirects, retries, cache poisoning, certificate
  failures, and offline recovery become product states;
- stronger source review and network-boundary tests are required to prove that
  meeting data has no egress path.

## Invariants shared by every option

- A committed Quill manifest identifies every model file, byte count, SHA-256,
  aggregate manifest hash, compatible FluidAudio version, license, and source.
- Model content is staged separately and becomes active only after complete
  verification.
- Missing, extra, modified, truncated, or unreadable content fails closed with
  a specific recovery action.
- No telemetry, crash uploader, analytics SDK, or generic HTTP client receives
  meeting-derived data.
- The model provisioning interface accepts only model identifiers and
  destinations; it cannot accept audio, transcript, annotation, identity, or
  summary values.
- A model change is versioned independently from transcript provenance.
- The active model is verified before load.

If Option C is selected:

- URLs and redirect destinations are allow-listed after DNS resolution;
- private, loopback, link-local, and metadata-service addresses are rejected;
- the download is content-length bounded;
- no credentials, cookies, arbitrary headers, or user-provided URLs are used;
- CI fails if another production module imports or constructs the network
  client;
- captured model provisioning traffic contains only the allow-listed model
  request/response, and capture plus transcription with an active model opens
  zero network connections.

## Required decision evidence

Measure the following for all applicable options:

1. clean installation download size;
2. app-only update size with an unchanged model;
3. update size with a changed model;
4. signing and notarization upload/processing time;
5. install, repair, rollback, and uninstall behavior;
6. peak temporary and final disk use;
7. cold/warm model load and verification time;
8. offline first-use behavior;
9. FluidAudio loading from the Quill-controlled location;
10. missing, modified, extra, truncated, and unreadable model failures;
11. static entitlements and production network imports;
12. captured network behavior during install, model provisioning, capture,
    first/ordinary transcription, export, and update.

The spike must include at least one full-size 600 MB payload. Estimates from a
small fixture are insufficient for update and notarization costs.

## Conditional decision

Conditionally select Option C, a Quill-owned hash-pinned first-use download,
because it satisfies the accepted small-DMG experience and keeps recording
independent from model readiness.

Acceptance of this ADR approves the provisioning decision process and the
conditional Option C direction. It does not clear Option C for production use.
The required full-size spike must still prove integrity, repair, offline
record-only behavior, FluidAudio loading from the activated location, final
entitlements, and captured meeting-data non-egress before production
implementation begins. If Option C fails a security objective or has no owned
repair path, architecture work stops for an amended decision; it does not
silently fall back to FluidAudio-managed downloads.

## Decision rule

Choose the lowest-complexity option that:

- proves both security objectives;
- meets the signed small-DMG plus explained first-use-download experience;
- keeps normal app-only update size and latency acceptable;
- has an exercised repair path;
- does not create an unowned update service.

Static absence of the network entitlement is a weighted security advantage for
Options A and B. It does not automatically outweigh measured update cost.

Record the final selected option, measurements, rejected tradeoffs, and
entitlements here before clearing the production-use block. Until then,
diagrams must show Option C as conditional and evidence-blocked.

## Verification

- Every single-file and manifest mutation fails before model activation.
- No unlisted file is trusted as model input.
- The packaged/downloaded model license and provenance are available locally.
- A clean install exercises the chosen first-use and offline behavior.
- Recording and imported-media adoption work before download and transcribe
  after a verified model becomes active.
- Options A/B open zero production network connections.
- Option C opens only allow-listed connections during explicit model
  provisioning; capture, transcription with an active model, and export open
  zero connections.
- Static checks match the selected entitlement and network-import boundary.
- Codesign, hardened runtime, notarization, stapling, and release-checksum
  checks cover every installed component.
