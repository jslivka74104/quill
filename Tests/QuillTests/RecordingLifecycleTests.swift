import Foundation
import Testing
@testable import quill

struct RecordingLifecycleTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let fixedSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test func startingManifestAndPrivateDirectoryPrecedeRecorderStart() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var preflightFinished = false
        var recorderStartCount = 0
        let preflight = RecordingRootPreflight(
            fileSystemName: { _ in "fixturefs" },
            probe: { _, _ in preflightFinished = true }
        )
        let recorder = RecordingTrackDriver.fixtureSystem(firstSampleAt: { fixedDate }) { destination in
            recorderStartCount += 1
            #expect(preflightFinished)

            let directory = destination.deletingLastPathComponent()
            #expect(try posixMode(of: directory) == 0o700)
            #expect(try posixMode(of: directory.appendingPathComponent("session.json")) == 0o600)
            #expect(try posixMode(of: destination) == 0o600)
            let manifest = try readManifest(in: directory)
            #expect(manifest.state == .starting)
            let json = try #require(
                JSONSerialization.jsonObject(
                    with: Data(contentsOf: directory.appendingPathComponent("session.json"))
                ) as? [String: Any]
            )
            #expect(json["schema_version"] as? Int == 2)
            #expect(json["capture_profile"] as? String == "online_meeting")
            #expect(json["capture_part_id"] as? String == "part-0001")
            #expect(json["failure"] is NSNull)
            #expect(json["started_at"] is NSNull)
            #expect(json["ended_at"] is NSNull)
        }
        let session = try RecordingSession(
            root: root,
            dependencies: dependencies(preflight: preflight, recorders: [recorder])
        )

        #expect(recorderStartCount == 0)
        try session.start()

        #expect(recorderStartCount == 1)
        let manifest = try readManifest(in: session.dir)
        #expect(manifest.state == .recording)
        assertTrackContract(manifest)
        #expect(manifest.tracks.map(\.captureStatus) == [.recording])
        #expect(manifest.tracks.map(\.startOffsetMs) == [0])
    }

    @Test func noLiveRecorderWritesObservedTypedFailure() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let recorders = [
            RecordingTrackDriver.fixtureSystem(
                firstSampleAt: { nil },
                start: { _ in throw FixtureFailure.systemStart }
            ),
            RecordingTrackDriver.fixtureMicrophone(
                firstSampleAt: { nil },
                start: { _ in throw FixtureFailure.microphoneStart }
            ),
        ]
        let session = try RecordingSession(
            root: root,
            dependencies: dependencies(recorders: recorders)
        )

        _ = try #require(throws: RecordingSessionError.self) {
            try session.start()
        }

        let manifest = try readManifest(in: session.dir)
        #expect(manifest.state == .failed)
        #expect(manifest.failure?.code == "no_live_tracks")
        #expect(manifest.failure?.phase == .starting)
        assertTrackContract(manifest)
        #expect(manifest.tracks.map(\.captureStatus) == [.missing, .missing])
        #expect(manifest.tracks.map { $0.failure?.code } == [
            "system_audio_start_failed",
            "microphone_start_failed",
        ])
    }

    @Test func destinationSecurityFailureHasSpecificTrackCode() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let unsafeDestination = RecordingTrackDriver(
            trackID: "system",
            role: .system,
            criticality: .primary,
            relativePath: "missing-parent/system.caf",
            startFailureCode: "system_audio_start_failed",
            start: { _ in Issue.record("recorder must not start with an unsecured destination") },
            stop: {},
            firstSampleAt: { nil }
        )
        let session = try RecordingSession(
            root: root,
            dependencies: dependencies(recorders: [unsafeDestination])
        )

        _ = try #require(throws: RecordingSessionError.self) {
            try session.start()
        }

        let manifest = try readManifest(in: session.dir)
        #expect(manifest.state == .failed)
        assertTrackContract(manifest)
        #expect(manifest.tracks.map { $0.failure?.code } == [
            "track_destination_security_failed"
        ])
    }

    @Test(arguments: [SessionLifecycleState.starting, .recording])
    func recoveryAloneAuthorsInterruptedWithoutSessionFailure(
        initialState: SessionLifecycleState
    ) throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let recorders = [
            RecordingTrackDriver.fixtureSystem(
                firstSampleAt: { fixedDate },
                start: { destination in
                    try Data("surviving-system-evidence".utf8).write(to: destination)
                }
            ),
            RecordingTrackDriver.fixtureMicrophone(
                firstSampleAt: { nil },
                start: { _ in throw FixtureFailure.microphoneStart }
            ),
        ]
        let session = try RecordingSession(
            root: root,
            dependencies: dependencies(recorders: recorders)
        )
        if initialState == .recording {
            try session.start()
        }
        let before = try readManifest(in: session.dir)
        let preservedTrackFailures = before.tracks.compactMap(\.failure)

        let report = try SessionLifecycleRecovery(
            now: { fixedDate.addingTimeInterval(10) },
            atomicWriter: .production
        ).recover(in: root)

        #expect(report.recovered.map(\.lastPathComponent) == [session.dir.lastPathComponent])
        #expect(report.failures.isEmpty)
        let manifest = try readManifest(in: session.dir)
        #expect(manifest.state == .interrupted)
        #expect(manifest.failure == nil)
        assertTrackContract(manifest)
        #expect(manifest.tracks.allSatisfy { $0.captureStatus != .pending })
        #expect(manifest.tracks.allSatisfy { $0.captureStatus != .recording })
        #expect(manifest.tracks.filter { $0.failure?.code != "process_terminated_unexpectedly" }
            .compactMap(\.failure) == preservedTrackFailures)
        #expect(manifest.tracks.filter { $0.captureStatus == .interrupted }
            .allSatisfy { $0.failure?.code == "process_terminated_unexpectedly" })
        #expect(
            try SessionTranscriptionEligibility.allowsTranscription(in: session.dir)
                == (initialState == .recording)
        )
    }

    @Test func transitionDeadlineBoundsARecorderStartCallAndAuthorsTimeout() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let recorderEntered = DispatchSemaphore(value: 0)
        let allowRecorderReturn = DispatchSemaphore(value: 0)
        let recorderReturned = DispatchSemaphore(value: 0)
        defer { allowRecorderReturn.signal() }

        let recorder = RecordingTrackDriver.fixtureSystem(
            firstSampleAt: { nil },
            start: { _ in
                recorderEntered.signal()
                allowRecorderReturn.wait()
                recorderReturned.signal()
            }
        )
        let session = try RecordingSession(
            root: root,
            dependencies: .testing(
                now: Date.init,
                preflight: .fixturePassing,
                recorders: [recorder],
                transitionTimeout: 0.02,
                pollInterval: 0.001
            )
        )

        _ = try #require(throws: RecordingSessionError.self) {
            try session.start()
        }

        #expect(recorderEntered.wait(timeout: .now() + 1) == .success)
        #expect(recorderReturned.wait(timeout: .now()) == .timedOut)
        let manifest = try readManifest(in: session.dir)
        #expect(manifest.state == .failed)
        assertTrackContract(manifest)
        #expect(manifest.tracks.map { $0.failure?.code } == ["start_timeout"])

        allowRecorderReturn.signal()
        #expect(recorderReturned.wait(timeout: .now() + 1) == .success)
    }

    @Test func recordingControllerKeepsMainActorResponsiveDuringStart() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let recorderEntered = AsyncStream<Void>.makeStream()
        let recorderEnteredContinuation = recorderEntered.continuation
        let allowRecorderReturn = DispatchSemaphore(value: 0)
        let recorderReturned = SynchronizedFlag()
        defer { allowRecorderReturn.signal() }

        let recorder = RecordingTrackDriver.fixtureSystem(
            firstSampleAt: { fixedDate },
            start: { _ in
                recorderEnteredContinuation.yield()
                recorderEnteredContinuation.finish()
                allowRecorderReturn.wait()
                recorderReturned.set()
            }
        )
        let controller = RecordingSessionController(
            root: root,
            dependencies: .testing(
                now: Date.init,
                preflight: .fixturePassing,
                recorders: [recorder],
                transitionTimeout: 5,
                pollInterval: 0.001
            )
        )

        let startTask = Task { try await controller.start() }
        var recorderEnteredIterator = recorderEntered.stream.makeAsyncIterator()
        let didEnterRecorder = await recorderEnteredIterator.next()
        #expect(didEnterRecorder != nil)

        await Task { @MainActor in }.value
        #expect(!recorderReturned.isSet)

        allowRecorderReturn.signal()
        let snapshot = try await startTask.value
        #expect(snapshot.directory.deletingLastPathComponent() == root)
        #expect(recorderReturned.isSet)
        _ = try await controller.stop()
    }

    @Test func corruptOldestManifestDoesNotBlockNewerRecovery() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let corrupt = root.appendingPathComponent("0000-corrupt", isDirectory: true)
        try PrivateFileSystem.createDirectory(corrupt)
        try AtomicFileWriter.production.write(
            Data("not-json".utf8),
            to: corrupt.appendingPathComponent("session.json")
        )
        let valid = try RecordingSession(
            root: root,
            dependencies: dependencies(
                recorders: [RecordingTrackDriver.fixtureSystem(firstSampleAt: { fixedDate })]
            )
        )

        let report = try SessionLifecycleRecovery(
            now: { fixedDate.addingTimeInterval(10) },
            atomicWriter: .production
        ).recover(in: root)

        #expect(report.recovered.map(\.lastPathComponent) == [valid.dir.lastPathComponent])
        #expect(report.failures.map { $0.directory.lastPathComponent } == [
            corrupt.lastPathComponent
        ])
        #expect(report.failures.map(\.kind) == [.unreadableManifest])
        let manifest = try readManifest(in: valid.dir)
        #expect(manifest.state == .interrupted)
        assertTrackContract(manifest)
    }

    @Test func futureManifestRemainsByteImmutableDuringRecovery() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try RecordingSession(
            root: root,
            dependencies: dependencies(
                recorders: [RecordingTrackDriver.fixtureSystem(firstSampleAt: { fixedDate })]
            )
        )
        let manifestURL = session.dir.appendingPathComponent("session.json")
        var json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        json["schema_version"] = 3
        json["future_evidence_authority"] = ["preserve": true]
        let futureBytes = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try AtomicFileWriter.production.write(futureBytes, to: manifestURL)

        let report = try SessionLifecycleRecovery(
            now: { fixedDate.addingTimeInterval(10) },
            atomicWriter: .production
        ).recover(in: root)

        #expect(report.recovered.isEmpty)
        #expect(report.failures.map(\.kind) == [.unsupportedSchemaVersion(3)])
        #expect(try Data(contentsOf: manifestURL) == futureBytes)
    }

    @Test func cleanCapturePromotesOnFirstSampleThenCompletesAfterFinalization() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var stoppedTracks: [String] = []
        let recorders = [
            RecordingTrackDriver.fixtureSystem(
                firstSampleAt: { fixedDate },
                start: { destination in
                    try Data("system-evidence".utf8).write(to: destination)
                },
                stop: { stoppedTracks.append("system") }
            ),
            RecordingTrackDriver.fixtureMicrophone(
                firstSampleAt: { fixedDate.addingTimeInterval(0.025) },
                start: { destination in
                    try Data("microphone-evidence".utf8).write(to: destination)
                },
                stop: { stoppedTracks.append("microphone") }
            ),
        ]
        let session = try RecordingSession(
            root: root,
            dependencies: dependencies(recorders: recorders)
        )

        try session.start()
        #expect(try readManifest(in: session.dir).state == .recording)

        try session.stop()

        #expect(stoppedTracks.sorted() == ["microphone", "system"])
        let manifest = try readManifest(in: session.dir)
        #expect(manifest.state == .complete)
        #expect(manifest.failure == nil)
        assertTrackContract(manifest)
        #expect(manifest.tracks.map(\.captureStatus) == [.complete, .complete])
        #expect(manifest.tracks.map(\.startOffsetMs) == [0, 25])
        #expect(manifest.tracks.map(\.durationMs) == [nil, nil])
        #expect(manifest.tracks.map(\.byteCount) == [15, 19])
        #expect(FileManager.default.fileExists(atPath: session.dir.appendingPathComponent("meta.json").path))
        #expect(try SessionTranscriptionEligibility.allowsTranscription(in: session.dir))
    }

    @Test func throwingRecorderStopPersistsOnlyTerminalTrackStates() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = RecordingTrackDriver.fixtureSystem(
            firstSampleAt: { fixedDate },
            start: { destination in
                try Data("intact-evidence".utf8).write(to: destination)
            },
            stop: { throw FixtureFailure.finalization }
        )
        let session = try RecordingSession(
            root: root,
            dependencies: dependencies(recorders: [recorder])
        )
        try session.start()

        let error = try #require(throws: RecordingSessionError.self) {
            try session.stop()
        }

        #expect(error.phase == .finalization)
        let manifest = try readManifest(in: session.dir)
        #expect(manifest.state == .failed)
        #expect(manifest.failure?.code == "recorder_finalization_failed")
        assertTrackContract(manifest)
        #expect(manifest.tracks.map(\.captureStatus) == [.complete])
        #expect(manifest.tracks.map(\.byteCount) == [15])
    }

    @Test func trackAttributeFailurePersistsInvalidTerminalTrack() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try RecordingSession(
            root: root,
            dependencies: dependencies(
                fileAttributes: { _ in throw FixtureFailure.attributes },
                recorders: [RecordingTrackDriver.fixtureSystem(firstSampleAt: { fixedDate })]
            )
        )
        try session.start()

        let error = try #require(throws: RecordingSessionError.self) {
            try session.stop()
        }

        #expect(error.phase == .finalization)
        let manifest = try readManifest(in: session.dir)
        #expect(manifest.state == .failed)
        assertTrackContract(manifest)
        #expect(manifest.tracks.map(\.captureStatus) == [.invalid])
        #expect(manifest.tracks.map { $0.failure?.code } == [
            "track_evidence_validation_failed"
        ])
    }

    @Test func terminalPersistenceFailureIsSpecificAndLeavesRecoverableState() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = AtomicFileWriter { data, destination in
            let manifest = try JSONDecoder.quill.decode(SessionManifest.self, from: data)
            if manifest.state == .complete {
                throw FixtureFailure.terminalWrite
            }
            try AtomicFileWriter.production.write(data, to: destination)
        }
        let session = try RecordingSession(
            root: root,
            dependencies: dependencies(
                atomicWriter: writer,
                recorders: [RecordingTrackDriver.fixtureSystem(firstSampleAt: { fixedDate })]
            )
        )
        try session.start()

        let error = try #require(throws: RecordingSessionError.self) {
            try session.stop()
        }

        #expect(error.phase == .terminalPersistence)
        let recording = try readManifest(in: session.dir)
        #expect(recording.state == .recording)
        assertTrackContract(recording)
        #expect(try !SessionTranscriptionEligibility.allowsTranscription(in: session.dir))
    }

    @Test func initialPersistenceFailureNeverStartsARecorder() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var recorderStartCount = 0
        let writer = AtomicFileWriter { _, _ in throw FixtureFailure.initialWrite }
        let recorder = RecordingTrackDriver.fixtureSystem(firstSampleAt: { fixedDate }) { _ in
            recorderStartCount += 1
        }

        let error = try #require(throws: RecordingSessionError.self) {
            _ = try RecordingSession(
                root: root,
                dependencies: dependencies(atomicWriter: writer, recorders: [recorder])
            )
        }

        #expect(error.phase == .startingPersistence)
        #expect(recorderStartCount == 0)
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        let directory = try #require(directories.first)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("session.json").path
        ))
    }

    @Test func failedPersistenceFailureFallsBackToRecoveryAuthorship() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = AtomicFileWriter { data, destination in
            let manifest = try JSONDecoder.quill.decode(SessionManifest.self, from: data)
            if manifest.state == .failed {
                throw FixtureFailure.failedWrite
            }
            try AtomicFileWriter.production.write(data, to: destination)
        }
        let recorder = RecordingTrackDriver.fixtureSystem(
            firstSampleAt: { nil },
            start: { _ in throw FixtureFailure.systemStart }
        )
        let session = try RecordingSession(
            root: root,
            dependencies: dependencies(atomicWriter: writer, recorders: [recorder])
        )

        let error = try #require(throws: RecordingSessionError.self) {
            try session.start()
        }
        #expect(error.phase == .terminalPersistence)
        let starting = try readManifest(in: session.dir)
        #expect(starting.state == .starting)
        assertTrackContract(starting)

        _ = try SessionLifecycleRecovery(
            now: { fixedDate.addingTimeInterval(10) },
            atomicWriter: .production
        ).recover(in: root)
        let recovered = try readManifest(in: session.dir)
        #expect(recovered.state == .interrupted)
        #expect(recovered.failure == nil)
        assertTrackContract(recovered)
    }

    @Test func terminalManifestRemainsByteImmutable() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try RecordingSession(
            root: root,
            dependencies: dependencies(
                recorders: [RecordingTrackDriver.fixtureSystem(firstSampleAt: { fixedDate })]
            )
        )
        try session.start()
        try session.stop()
        let manifestURL = session.dir.appendingPathComponent("session.json")
        let terminalBytes = try Data(contentsOf: manifestURL)

        _ = try #require(throws: RecordingSessionError.self) {
            try session.stop()
        }
        assertTrackContract(try readManifest(in: session.dir))
        let report = try SessionLifecycleRecovery(
            now: { fixedDate.addingTimeInterval(10) },
            atomicWriter: .production
        ).recover(in: root)

        #expect(report.recovered.isEmpty)
        #expect(report.failures.isEmpty)
        #expect(try Data(contentsOf: manifestURL) == terminalBytes)
    }

    @Test(arguments: crashExpectations)
    func lifecycleCrashMatrixLeavesTruthfulState(expectation: CrashExpectation) throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let deps = dependencies(
            recorders: [
                .fixtureSystem(firstSampleAt: { fixedDate }),
                .fixtureMicrophone(firstSampleAt: { fixedDate }),
            ],
            interruptAt: { $0 == expectation.boundary }
        )

        var sessionDirectory: URL?
        do {
            let session = try RecordingSession(root: root, dependencies: deps)
            sessionDirectory = session.dir
            try session.start()
            try session.stop()
        } catch RecordingSessionError.injectedInterruption(let directory, _) {
            sessionDirectory = directory
        }

        let directory = try #require(sessionDirectory)
        let manifestURL = directory.appendingPathComponent("session.json")
        if let expectedState = expectation.persistedState {
            #expect(FileManager.default.fileExists(atPath: manifestURL.path))
            let persisted = try readManifest(in: directory)
            #expect(persisted.state == expectedState)
            assertTrackContract(persisted)

            if expectedState == .starting || expectedState == .recording {
                _ = try SessionLifecycleRecovery(
                    now: { fixedDate.addingTimeInterval(10) },
                    atomicWriter: .production
                ).recover(in: root)
                let interrupted = try readManifest(in: directory)
                #expect(interrupted.state == .interrupted)
                assertTrackContract(interrupted)
            }
        } else {
            #expect(!FileManager.default.fileExists(atPath: manifestURL.path))
        }
    }

    private static let crashExpectations: [CrashExpectation] = [
        .init(boundary: .directoryCreated, persistedState: nil),
        .init(boundary: .startingPersisted, persistedState: .starting),
        .init(boundary: .recorderStarted(trackID: "system"), persistedState: .starting),
        .init(boundary: .recorderStartsResolved, persistedState: .starting),
        .init(boundary: .recordingPersisted, persistedState: .recording),
        .init(boundary: .recordersFinalized, persistedState: .recording),
        .init(boundary: .legacyMetadataPersisted, persistedState: .recording),
        .init(boundary: .terminalPersisted, persistedState: .complete),
    ]

    struct CrashExpectation: CustomTestStringConvertible, Sendable {
        let boundary: RecordingLifecycleBoundary
        let persistedState: SessionLifecycleState?

        var testDescription: String {
            "\(boundary) -> \(persistedState?.rawValue ?? "no manifest")"
        }
    }

    private enum FixtureFailure: Error {
        case systemStart
        case microphoneStart
        case initialWrite
        case failedWrite
        case terminalWrite
        case finalization
        case attributes
    }

    private func dependencies(
        preflight: RecordingRootPreflight = .fixturePassing,
        atomicWriter: AtomicFileWriter = .production,
        fileAttributes: @escaping (URL) throws -> [FileAttributeKey: Any] = {
            try FileManager.default.attributesOfItem(atPath: $0.path)
        },
        recorders: [RecordingTrackDriver],
        interruptAt: @escaping (RecordingLifecycleBoundary) -> Bool = { _ in false }
    ) -> RecordingSession.Dependencies {
        .testing(
            now: { fixedDate },
            sessionID: { fixedSessionID },
            preflight: preflight,
            atomicWriter: atomicWriter,
            fileAttributes: fileAttributes,
            recorders: recorders,
            transitionTimeout: 0,
            interruptAt: interruptAt
        )
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    private func readManifest(in directory: URL) throws -> SessionManifest {
        let data = try Data(contentsOf: directory.appendingPathComponent("session.json"))
        return try JSONDecoder.quill.decode(SessionManifest.self, from: data)
    }

    private func posixMode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    private func assertTrackContract(
        _ manifest: SessionManifest,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for track in manifest.tracks {
            switch track.captureStatus {
            case .pending, .recording, .complete:
                #expect(track.failure == nil, sourceLocation: sourceLocation)
            case .degraded, .interrupted, .missing, .invalid:
                #expect(track.failure != nil, sourceLocation: sourceLocation)
            }
        }
        if manifest.state.isTerminal {
            #expect(
                manifest.tracks.allSatisfy {
                    $0.captureStatus != .pending && $0.captureStatus != .recording
                },
                sourceLocation: sourceLocation
            )
        }
    }
}

private final class SynchronizedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

private extension RecordingRootPreflight {
    static var fixturePassing: RecordingRootPreflight {
        RecordingRootPreflight(
            fileSystemName: { _ in "fixturefs" },
            probe: { _, _ in }
        )
    }
}

extension RecordingTrackDriver {
    static func fixtureSystem(
        firstSampleAt: @escaping () -> Date?,
        start: @escaping (URL) throws -> Void = { _ in },
        stop: @escaping () throws -> Void = {}
    ) -> RecordingTrackDriver {
        RecordingTrackDriver(
            trackID: "system",
            role: .system,
            criticality: .primary,
            relativePath: "system.caf",
            startFailureCode: "system_audio_start_failed",
            start: start,
            stop: stop,
            firstSampleAt: firstSampleAt
        )
    }

    static func fixtureMicrophone(
        firstSampleAt: @escaping () -> Date?,
        start: @escaping (URL) throws -> Void = { _ in },
        stop: @escaping () throws -> Void = {}
    ) -> RecordingTrackDriver {
        RecordingTrackDriver(
            trackID: "microphone",
            role: .microphone,
            criticality: .secondary,
            relativePath: "mic.caf",
            startFailureCode: "microphone_start_failed",
            start: start,
            stop: stop,
            firstSampleAt: firstSampleAt
        )
    }
}
