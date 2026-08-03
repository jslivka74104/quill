import Foundation

enum RecordingLifecycleBoundary: Equatable, Sendable, CustomStringConvertible {
    case directoryCreated
    case startingPersisted
    case recorderStarted(trackID: String)
    case recorderStartsResolved
    case recordingPersisted
    case recordersFinalized
    case legacyMetadataPersisted
    case terminalPersisted

    var description: String {
        switch self {
        case .directoryCreated: return "directory_created"
        case .startingPersisted: return "starting_persisted"
        case .recorderStarted(let trackID): return "recorder_started(\(trackID))"
        case .recorderStartsResolved: return "recorder_starts_resolved"
        case .recordingPersisted: return "recording_persisted"
        case .recordersFinalized: return "recorders_finalized"
        case .legacyMetadataPersisted: return "legacy_metadata_persisted"
        case .terminalPersisted: return "terminal_persisted"
        }
    }
}

enum RecordingSessionOperationPhase: Equatable, Sendable {
    case directoryCreation
    case startingPersistence
    case recorderStart
    case recordingPersistence
    case finalization
    case legacyMetadataPersistence
    case terminalPersistence
    case invalidTransition
    case injectedInterruption
}

enum RecordingSessionError: Error, CustomStringConvertible, Sendable {
    case operationFailed(RecordingSessionOperationPhase, FailureContext)
    case noLiveTracks(SessionFailure)
    case invalidTransition(from: SessionLifecycleState, operation: String)
    case injectedInterruption(URL, RecordingLifecycleBoundary)

    var phase: RecordingSessionOperationPhase {
        switch self {
        case .operationFailed(let phase, _): return phase
        case .noLiveTracks: return .recorderStart
        case .invalidTransition: return .invalidTransition
        case .injectedInterruption: return .injectedInterruption
        }
    }

    var description: String {
        switch self {
        case .operationFailed(let phase, let context):
            return "recording \(phase) failed: \(context.message)"
        case .noLiveTracks(let failure):
            return failure.message
        case .invalidTransition(let state, let operation):
            return "cannot \(operation) a session in \(state.rawValue)"
        case .injectedInterruption(_, let boundary):
            return "injected interruption at \(boundary)"
        }
    }
}

struct RecordingTrackDriver {
    let trackID: String
    let role: SessionTrackRole
    let criticality: SessionTrackCriticality
    let relativePath: String
    let startFailureCode: String
    let start: (URL) throws -> Void
    let stop: () throws -> Void
    let firstSampleAt: () -> Date?
}

private final class RecorderStartAttempt: @unchecked Sendable {
    private let recorder: RecordingTrackDriver
    private let destination: URL
    private let completion = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var outcome: Result<Void, Error>?
    private var expired = false

    init(recorder: RecordingTrackDriver, destination: URL) {
        self.recorder = recorder
        self.destination = destination
    }

    func launch() {
        Thread.detachNewThread { [self] in
            let result = Result { try recorder.start(destination) }
            lock.lock()
            let shouldStopLateStart = expired && result.isSuccess
            if !expired {
                outcome = result
            }
            lock.unlock()

            if shouldStopLateStart {
                do { try recorder.stop() } catch { }
            }
            completion.signal()
        }
    }

    func wait(timeout: TimeInterval) -> Result<Void, Error>? {
        let waitResult = completion.wait(timeout: .now() + max(0, timeout))
        lock.lock()
        defer { lock.unlock() }
        if let outcome { return outcome }
        if waitResult == .timedOut {
            expired = true
        }
        return nil
    }
}

private extension Result where Success == Void, Failure == Error {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// One meeting recording with a durable lifecycle authority. The selected root
/// is preflighted before evidence exists, then a private directory and atomic
/// `starting` manifest precede both recorder start calls.
final class RecordingSession {
    struct Dependencies {
        let now: () -> Date
        let sessionID: () -> UUID
        let preflight: RecordingRootPreflight
        let atomicWriter: AtomicFileWriter
        let metadataWriter: AtomicFileWriter
        let fileAttributes: (URL) throws -> [FileAttributeKey: Any]
        let recorders: [RecordingTrackDriver]
        let monotonicNow: () -> TimeInterval
        let transitionTimeout: TimeInterval
        let pollInterval: TimeInterval
        let interruptAt: (RecordingLifecycleBoundary) -> Bool

        static func testing(
            now: @escaping () -> Date = Date.init,
            sessionID: @escaping () -> UUID = UUID.init,
            preflight: RecordingRootPreflight,
            atomicWriter: AtomicFileWriter = .production,
            metadataWriter: AtomicFileWriter = .production,
            fileAttributes: @escaping (URL) throws -> [FileAttributeKey: Any] = {
                try FileManager.default.attributesOfItem(atPath: $0.path)
            },
            recorders: [RecordingTrackDriver],
            monotonicNow: @escaping () -> TimeInterval = {
                ProcessInfo.processInfo.systemUptime
            },
            transitionTimeout: TimeInterval = 0,
            pollInterval: TimeInterval = 0,
            interruptAt: @escaping (RecordingLifecycleBoundary) -> Bool = { _ in false }
        ) -> Dependencies {
            Dependencies(
                now: now,
                sessionID: sessionID,
                preflight: preflight,
                atomicWriter: atomicWriter,
                metadataWriter: metadataWriter,
                fileAttributes: fileAttributes,
                recorders: recorders,
                monotonicNow: monotonicNow,
                transitionTimeout: transitionTimeout,
                pollInterval: pollInterval,
                interruptAt: interruptAt
            )
        }

        static func production() -> Dependencies {
            let microphone = MicRecorder()
            let system = SystemAudioRecorder()
            return Dependencies(
                now: Date.init,
                sessionID: UUID.init,
                preflight: .production(),
                atomicWriter: .production,
                metadataWriter: .production,
                fileAttributes: {
                    try FileManager.default.attributesOfItem(atPath: $0.path)
                },
                recorders: [
                    RecordingTrackDriver(
                        trackID: "system",
                        role: .system,
                        criticality: .primary,
                        relativePath: "system.caf",
                        startFailureCode: "system_audio_start_failed",
                        start: { try system.start(writingTo: $0) },
                        stop: { system.stop() },
                        firstSampleAt: { system.firstBufferAt }
                    ),
                    RecordingTrackDriver(
                        trackID: "microphone",
                        role: .microphone,
                        criticality: .secondary,
                        relativePath: "mic.caf",
                        startFailureCode: "microphone_start_failed",
                        start: { try microphone.start(writingTo: $0) },
                        stop: { microphone.stop() },
                        firstSampleAt: { microphone.firstBufferAt }
                    ),
                ],
                monotonicNow: { ProcessInfo.processInfo.systemUptime },
                transitionTimeout: 3,
                pollInterval: 0.01,
                interruptAt: { _ in false }
            )
        }
    }

    let dir: URL
    let startedAt: Date

    private let dependencies: Dependencies
    private var manifest: SessionManifest
    private var startedTrackIDs: Set<String> = []

    private static let folderFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd-HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    convenience init(root: URL) throws {
        try self.init(root: root, dependencies: .production())
    }

    init(root: URL, dependencies: Dependencies) throws {
        try dependencies.preflight.validate(root)

        let createdAt = dependencies.now()
        let directory = Self.availableDirectory(in: root, at: createdAt)
        do {
            try PrivateFileSystem.createDirectory(directory)
        } catch {
            throw RecordingSessionError.operationFailed(.directoryCreation, FailureContext(error))
        }

        let tracks = dependencies.recorders.map {
            SessionTrack(
                trackID: $0.trackID,
                partID: "part-0001",
                role: $0.role,
                criticality: $0.criticality,
                relativePath: $0.relativePath,
                mediaType: "audio/x-caf"
            )
        }
        let initialManifest = SessionManifest(
            sessionID: dependencies.sessionID(),
            createdAt: createdAt,
            tracks: tracks
        )

        dir = directory
        startedAt = createdAt
        self.dependencies = dependencies
        manifest = initialManifest

        try injectInterruption(at: .directoryCreated)
        do {
            try persist(initialManifest)
        } catch {
            throw RecordingSessionError.operationFailed(.startingPersistence, FailureContext(error))
        }
        try injectInterruption(at: .startingPersisted)
    }

    func start() throws {
        guard manifest.state == .starting else {
            throw RecordingSessionError.invalidTransition(from: manifest.state, operation: "start")
        }

        var prepared: [(recorder: RecordingTrackDriver, destination: URL)] = []
        for recorder in dependencies.recorders {
            let destination = dir.appendingPathComponent(recorder.relativePath)
            do {
                try PrivateFileSystem.preparePrivateFile(destination)
            } catch {
                recordStartFailure(
                    error,
                    for: recorder,
                    code: "track_destination_security_failed"
                )
                continue
            }
            prepared.append((recorder, destination))
        }

        let transitionDeadline = dependencies.monotonicNow()
            + dependencies.transitionTimeout
        if dependencies.transitionTimeout <= 0 {
            for item in prepared {
                try startSynchronously(item.recorder, destination: item.destination)
            }
        } else {
            let attempts = prepared.map { item in
                (
                    recorder: item.recorder,
                    destination: item.destination,
                    attempt: RecorderStartAttempt(
                        recorder: item.recorder,
                        destination: item.destination
                    )
                )
            }
            attempts.forEach { $0.attempt.launch() }

            for item in attempts {
                let remaining = max(0, transitionDeadline - dependencies.monotonicNow())
                guard let outcome = item.attempt.wait(timeout: remaining) else {
                    recordStartTimeout(for: item.recorder)
                    continue
                }
                switch outcome {
                case .success:
                    try finishSuccessfulStart(
                        item.recorder,
                        destination: item.destination
                    )
                case .failure(let error):
                    recordStartFailure(error, for: item.recorder)
                }
            }
        }

        waitForRecorderResolution(deadline: transitionDeadline)
        resolveTrackLiveness()
        try injectInterruption(at: .recorderStartsResolved)

        let liveSamples = dependencies.recorders.compactMap { recorder -> Date? in
            guard manifest.tracks.first(where: { $0.trackID == recorder.trackID })?.failure == nil else {
                return nil
            }
            return recorder.firstSampleAt()
        }

        guard let earliestSample = liveSamples.min() else {
            stopStartedRecordersIgnoringSecondaryFailures()
            let observedAt = dependencies.now()
            let failure = SessionFailure(
                code: "no_live_tracks",
                phase: .starting,
                message: "No requested recorder delivered a first sample.",
                observedAt: observedAt
            )
            var failed = manifest
            failed.revision += 1
            failed.state = .failed
            failed.failure = failure
            failed.endedAt = observedAt
            do {
                try persist(failed)
                manifest = failed
            } catch {
                throw RecordingSessionError.operationFailed(
                    .terminalPersistence,
                    FailureContext(error)
                )
            }
            throw RecordingSessionError.noLiveTracks(failure)
        }

        var recording = manifest
        recording.revision += 1
        recording.state = .recording
        recording.startedAt = earliestSample
        for index in recording.tracks.indices {
            guard let recorder = dependencies.recorders.first(where: {
                $0.trackID == recording.tracks[index].trackID
            }), let sample = recorder.firstSampleAt(), recording.tracks[index].failure == nil else {
                continue
            }
            recording.tracks[index].captureStatus = .recording
            recording.tracks[index].startOffsetMs = max(
                0,
                Int((sample.timeIntervalSince(earliestSample) * 1_000).rounded())
            )
        }
        do {
            try persist(recording)
            manifest = recording
        } catch {
            stopStartedRecordersIgnoringSecondaryFailures()
            throw RecordingSessionError.operationFailed(
                .recordingPersistence,
                FailureContext(error)
            )
        }
        try injectInterruption(at: .recordingPersisted)
    }

    func stop() throws {
        guard manifest.state == .recording else {
            throw RecordingSessionError.invalidTransition(from: manifest.state, operation: "stop")
        }

        for recorder in dependencies.recorders where startedTrackIDs.contains(recorder.trackID) {
            do {
                try recorder.stop()
            } catch {
                try persistObservedFinalizationFailure(error)
                throw RecordingSessionError.operationFailed(.finalization, FailureContext(error))
            }
        }
        startedTrackIDs.removeAll()
        try injectInterruption(at: .recordersFinalized)

        let endedAt = dependencies.now()
        do {
            try dependencies.metadataWriter.write(
                try legacyMetadata(endedAt: endedAt),
                to: dir.appendingPathComponent("meta.json")
            )
        } catch {
            throw RecordingSessionError.operationFailed(
                .legacyMetadataPersistence,
                FailureContext(error)
            )
        }
        try injectInterruption(at: .legacyMetadataPersisted)

        var complete = manifest
        complete.revision += 1
        complete.state = .complete
        complete.failure = nil
        complete.endedAt = endedAt
        if let captureStart = complete.startedAt {
            complete.durationMs = max(0, Int(endedAt.timeIntervalSince(captureStart) * 1_000))
        }
        for index in complete.tracks.indices where complete.tracks[index].captureStatus == .recording {
            do {
                try completeTrack(&complete.tracks[index])
            } catch {
                try persistObservedFinalizationFailure(error)
                throw RecordingSessionError.operationFailed(
                    .finalization,
                    FailureContext(error)
                )
            }
        }
        do {
            try persist(complete)
            manifest = complete
        } catch {
            throw RecordingSessionError.operationFailed(
                .terminalPersistence,
                FailureContext(error)
            )
        }
        try injectInterruption(at: .terminalPersisted)
    }

    private func startSynchronously(
        _ recorder: RecordingTrackDriver,
        destination: URL
    ) throws {
        do {
            try recorder.start(destination)
        } catch {
            recordStartFailure(error, for: recorder)
            return
        }
        try finishSuccessfulStart(recorder, destination: destination)
    }

    private func finishSuccessfulStart(
        _ recorder: RecordingTrackDriver,
        destination: URL
    ) throws {
        do {
            try PrivateFileSystem.securePrivateFile(destination)
        } catch {
            do { try recorder.stop() } catch { }
            recordStartFailure(
                error,
                for: recorder,
                code: "track_destination_security_failed"
            )
            return
        }
        startedTrackIDs.insert(recorder.trackID)
        try injectInterruption(at: .recorderStarted(trackID: recorder.trackID))
    }

    private func waitForRecorderResolution(deadline: TimeInterval) {
        while dependencies.monotonicNow() < deadline {
            let allResolved = dependencies.recorders.allSatisfy { recorder in
                manifest.tracks.first(where: { $0.trackID == recorder.trackID })?.failure != nil
                    || recorder.firstSampleAt() != nil
            }
            if allResolved { return }
            Thread.sleep(forTimeInterval: dependencies.pollInterval)
        }
    }

    private func recordStartTimeout(for recorder: RecordingTrackDriver) {
        guard let index = manifest.tracks.firstIndex(where: { $0.trackID == recorder.trackID }) else {
            return
        }
        manifest.tracks[index].captureStatus = .missing
        manifest.tracks[index].failure = SessionTrackFailure(
            code: "start_timeout",
            message: "Recorder start did not return before the transition deadline.",
            observedAt: dependencies.now(),
            recoveryAttempted: false
        )
    }

    private func resolveTrackLiveness() {
        let observedAt = dependencies.now()
        for index in manifest.tracks.indices {
            guard manifest.tracks[index].failure == nil,
                  let recorder = dependencies.recorders.first(where: {
                      $0.trackID == manifest.tracks[index].trackID
                  })
            else { continue }

            if recorder.firstSampleAt() == nil {
                manifest.tracks[index].captureStatus = .missing
                manifest.tracks[index].failure = SessionTrackFailure(
                    code: "start_timeout",
                    message: "Recorder started but delivered no first sample before the transition deadline.",
                    observedAt: observedAt,
                    recoveryAttempted: false
                )
            }
        }
    }

    private func recordStartFailure(
        _ error: Error,
        for recorder: RecordingTrackDriver,
        code: String? = nil
    ) {
        guard let index = manifest.tracks.firstIndex(where: { $0.trackID == recorder.trackID }) else {
            return
        }
        manifest.tracks[index].captureStatus = .missing
        manifest.tracks[index].failure = SessionTrackFailure(
            code: code ?? recorder.startFailureCode,
            message: String(describing: error),
            observedAt: dependencies.now(),
            recoveryAttempted: false
        )
    }

    private func persistObservedFinalizationFailure(_ error: Error) throws {
        let observedAt = dependencies.now()
        var failed = manifest
        failed.revision += 1
        failed.state = .failed
        failed.failure = SessionFailure(
            code: "recorder_finalization_failed",
            phase: .finalization,
            message: String(describing: error),
            observedAt: observedAt
        )
        failed.endedAt = observedAt
        for index in failed.tracks.indices
        where failed.tracks[index].captureStatus == .pending
            || failed.tracks[index].captureStatus == .recording
        {
            do {
                try completeTrack(&failed.tracks[index])
            } catch {
                failed.tracks[index].captureStatus = .invalid
                failed.tracks[index].failure = SessionTrackFailure(
                    code: "track_evidence_validation_failed",
                    message: String(describing: error),
                    observedAt: observedAt,
                    recoveryAttempted: false
                )
            }
        }
        do {
            try persist(failed)
            manifest = failed
        } catch {
            throw RecordingSessionError.operationFailed(
                .terminalPersistence,
                FailureContext(error)
            )
        }
    }

    private func completeTrack(_ track: inout SessionTrack) throws {
        let media = dir.appendingPathComponent(track.relativePath)
        let attributes = try dependencies.fileAttributes(media)
        guard let size = attributes[.size] as? NSNumber else {
            throw RecordingEvidenceValidationError.missingByteCount(media)
        }
        track.captureStatus = .complete
        track.failure = nil
        track.byteCount = size.intValue
    }

    private func stopStartedRecordersIgnoringSecondaryFailures() {
        for recorder in dependencies.recorders where startedTrackIDs.contains(recorder.trackID) {
            do { try recorder.stop() } catch { }
        }
        startedTrackIDs.removeAll()
    }

    private func persist(_ manifest: SessionManifest) throws {
        try dependencies.atomicWriter.write(
            try JSONEncoder.quill.encode(manifest),
            to: dir.appendingPathComponent("session.json")
        )
    }

    private func legacyMetadata(endedAt: Date) throws -> Data {
        let firstSamples = Dictionary(
            uniqueKeysWithValues: dependencies.recorders.map {
                ($0.trackID, $0.firstSampleAt() ?? startedAt)
            }
        )
        let earliest = firstSamples.values.min() ?? startedAt
        let iso = ISO8601DateFormatter()
        let metadata: [String: Any] = [
            "started": iso.string(from: startedAt),
            "ended": iso.string(from: endedAt),
            "duration_seconds": Int(endedAt.timeIntervalSince(startedAt)),
            "files": ["mic": "mic.caf", "system": "system.caf"],
            "start_offset_ms": [
                "mic": Int((firstSamples["microphone"] ?? startedAt).timeIntervalSince(earliest) * 1_000),
                "system": Int((firstSamples["system"] ?? startedAt).timeIntervalSince(earliest) * 1_000),
            ],
        ]
        return try JSONSerialization.data(
            withJSONObject: metadata,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private func injectInterruption(at boundary: RecordingLifecycleBoundary) throws {
        guard dependencies.interruptAt(boundary) else { return }
        throw RecordingSessionError.injectedInterruption(dir, boundary)
    }

    private static func availableDirectory(in root: URL, at date: Date) -> URL {
        let base = folderFormat.string(from: date)
        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }
}

private enum RecordingEvidenceValidationError: Error, CustomStringConvertible {
    case missingByteCount(URL)

    var description: String {
        switch self {
        case .missingByteCount(let url):
            return "recorded evidence has no byte count: \(url.path)"
        }
    }
}

struct RecordingSessionSnapshot: Equatable, Sendable {
    let directory: URL
    let startedAt: Date
}

/// Owns the non-Sendable recorder graph on a dedicated actor so synchronous
/// permission prompts and liveness waits never block AppKit's main actor.
actor RecordingSessionController {
    private let root: URL
    private let dependencies: RecordingSession.Dependencies?
    private var session: RecordingSession?

    init(
        root: URL,
        dependencies: RecordingSession.Dependencies? = nil
    ) {
        self.root = root
        self.dependencies = dependencies
    }

    func start() throws -> RecordingSessionSnapshot {
        let newSession: RecordingSession
        if let dependencies {
            newSession = try RecordingSession(root: root, dependencies: dependencies)
        } else {
            newSession = try RecordingSession(root: root)
        }
        try newSession.start()
        session = newSession
        return RecordingSessionSnapshot(
            directory: newSession.dir,
            startedAt: newSession.startedAt
        )
    }

    func stop() throws -> RecordingSessionSnapshot? {
        guard let session else { return nil }
        try session.stop()
        self.session = nil
        return RecordingSessionSnapshot(
            directory: session.dir,
            startedAt: session.startedAt
        )
    }
}
