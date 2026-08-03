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
        #expect(try readManifest(in: session.dir).state == .recording)
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
        #expect(manifest.tracks.allSatisfy { $0.failure != nil })
    }

    @Test(arguments: [SessionLifecycleState.starting, .recording])
    func recoveryAloneAuthorsInterruptedWithoutSessionFailure(
        initialState: SessionLifecycleState
    ) throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let recorders = [
            RecordingTrackDriver.fixtureSystem(firstSampleAt: { fixedDate }),
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

        let recovered = try SessionLifecycleRecovery(
            now: { fixedDate.addingTimeInterval(10) },
            atomicWriter: .production
        ).recover(in: root)

        #expect(recovered.map(\.lastPathComponent) == [session.dir.lastPathComponent])
        let manifest = try readManifest(in: session.dir)
        #expect(manifest.state == .interrupted)
        #expect(manifest.failure == nil)
        #expect(manifest.tracks.compactMap(\.failure) == preservedTrackFailures)
        #expect(try !SessionTranscriptionEligibility.allowsTranscription(in: session.dir))
    }

    @Test func cleanCapturePromotesOnFirstSampleThenCompletesAfterFinalization() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        var stoppedTracks: [String] = []
        let recorders = [
            RecordingTrackDriver.fixtureSystem(
                firstSampleAt: { fixedDate },
                stop: { stoppedTracks.append("system") }
            ),
            RecordingTrackDriver.fixtureMicrophone(
                firstSampleAt: { fixedDate.addingTimeInterval(0.025) },
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
        #expect(FileManager.default.fileExists(atPath: session.dir.appendingPathComponent("meta.json").path))
        #expect(try SessionTranscriptionEligibility.allowsTranscription(in: session.dir))
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
        #expect(try readManifest(in: session.dir).state == .recording)
        #expect(try !SessionTranscriptionEligibility.allowsTranscription(in: session.dir))
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
            #expect(try readManifest(in: directory).state == expectedState)

            if expectedState == .starting || expectedState == .recording {
                _ = try SessionLifecycleRecovery(
                    now: { fixedDate.addingTimeInterval(10) },
                    atomicWriter: .production
                ).recover(in: root)
                #expect(try readManifest(in: directory).state == .interrupted)
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
        case terminalWrite
    }

    private func dependencies(
        preflight: RecordingRootPreflight = .fixturePassing,
        atomicWriter: AtomicFileWriter = .production,
        recorders: [RecordingTrackDriver],
        interruptAt: @escaping (RecordingLifecycleBoundary) -> Bool = { _ in false }
    ) -> RecordingSession.Dependencies {
        .testing(
            now: { fixedDate },
            sessionID: { fixedSessionID },
            preflight: preflight,
            atomicWriter: atomicWriter,
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
