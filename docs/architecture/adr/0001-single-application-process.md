# ADR 0001: Begin with one application process

Status: **Accepted**
Date: 2026-07-29

## Context

Quill is currently one executable that owns its menu bar, recording state, and
transcription queue. The new product adds a regular SwiftUI library window,
word playback, imports, and exports. A helper could isolate recording from GUI
failure, but would also add IPC, permission ownership, signing, launch,
version-skew, and update failure modes before Quill has evidence that it needs
independent survival.

The current install is a bare ad hoc linker-signed executable with no Team ID
or notarization. Its embedded linker-section `Info.plist` exists so TCC can
attribute permissions without an app bundle. Moving to a Developer ID `.app`
therefore changes identity and requires existing users to approve microphone
and System Audio Recording access again.

Package metadata already requires macOS 15 even though the Core Audio tap API
exists on macOS 14.2. No exercised 14.x matrix covers TCC onboarding, capture,
interruption recovery, signing, and packaging. The architecture keeps macOS 15
as one declared product/test floor until a separate compatibility decision
supplies that evidence.

## Decision

Ship one Developer ID-signed SwiftUI `.app` process supporting macOS 15 or
later. It owns a normal window scene, a menu-bar control, capture, local
transcription, scheduling, and storage adapters.

Recording is isolated behind `CaptureCoordinator` and actor/protocol
boundaries. Closing a window does not terminate the app. Explicit quit while
recording must stop and finalize or require a deliberate user decision.
Interrupted CAF tracks are recovered on next launch and the session is marked
`interrupted`.

Use `SMAppService.mainApp` for optional launch at login. Do not install a
LaunchAgent, daemon, XPC service, or privileged helper.

Capture and transcription are independent. Recording can begin before the
model is installed and can continue while earlier work is queued. The
transcription scheduler may run immediately or while the Mac is awake and
idle, pause for active recording or user activity, and prevent idle system
sleep only while processing. It does not promise work during system sleep,
schedule a privileged wake, or make capture depend on model readiness.

Migration onboarding detects the legacy launch path, explains that TCC
re-approval is required, unregisters the old LaunchAgent with explicit user
consent, and walks both permission paths. It never manipulates the TCC database
or claims that old grants transfer.

## Consequences

- One bundle owns microphone/system-audio permission and user onboarding.
- One bundle owns durable transcription ordering and awake-idle execution
  without a second launch mechanism.
- Signing, notarization, updates, and diagnostics have one version boundary.
- Existing users see a one-time, user-visible permission migration.
- README, package metadata, source comments, CI, and release checks use macOS
  15 as the same minimum.
- A process crash ends active capture; recovery preserves readable media but
  cannot claim the session completed.
- Internal seams must be real enough that a helper can be introduced later
  without exposing SwiftUI or SQLite types in the capture contract.

## Alternatives rejected

### GUI plus recorder helper now

Rejected because it creates operational complexity without satisfying the
minimum vertical slice. A helper does not make capture reliable by itself; it
adds IPC loss, dual-process crash handling, permission attribution, and update
coordination that would all need proof.

### Keep a command-line daemon plus a separate GUI

Rejected because it retains the current installation and permission
attribution problems and makes the GUI a second product surface over an
unversioned protocol.

## Verification

- Closing and reopening the library window does not interrupt recording.
- Explicit Quit while recording cannot silently lose the session.
- Forced process termination yields an `interrupted`, recoverable session.
- Mic/system permission onboarding is exercised in the signed app.
- Migration from the bare executable proves that both TCC grants are requested
  again and the legacy LaunchAgent is removed safely.
- Login-at-launch uses the main app service and survives relaunch.
- Recording succeeds while the model is unavailable and transcribes later.
- Idle transcription pauses for recording/user activity, survives sleep, and
  resumes without corrupting a generation.
- A release check rejects a deployment target below macOS 15 or contradictory
  support claims.

## Reconsider when

- capture must survive GUI termination;
- measured GUI crashes threaten recordings;
- capture must restart independently;
- a required entitlement can only be isolated safely in another process.

A change requires a replacement ADR and tests for IPC loss, helper/main-app
version skew, permissions, updates, and simultaneous failure.
