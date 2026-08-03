import Foundation
import Testing
@testable import quill

struct TranscriptionRecoveryTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func resumePendingQueuesRecoveredSessionWithoutLegacyMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-transcription-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let preflight = RecordingRootPreflight(
            fileSystemName: { _ in "fixturefs" },
            probe: { _, _ in }
        )
        let recorder = RecordingTrackDriver.fixtureSystem(
            firstSampleAt: { fixedDate },
            start: { destination in
                try Data("surviving-system-evidence".utf8).write(to: destination)
            }
        )
        let session = try RecordingSession(
            root: root,
            dependencies: .testing(
                now: { fixedDate },
                preflight: preflight,
                recorders: [recorder],
                transitionTimeout: 0
            )
        )
        try session.start()
        let report = try SessionLifecycleRecovery(
            now: { fixedDate.addingTimeInterval(10) },
            atomicWriter: .production
        ).recover(in: root)

        #expect(!FileManager.default.fileExists(
            atPath: session.dir.appendingPathComponent("meta.json").path
        ))
        #expect(report.recovered.map(\.lastPathComponent) == [session.dir.lastPathComponent])
        #expect(try SessionTranscriptionEligibility.allowsTranscription(in: session.dir))

        let coordinator = TranscriptionCoordinator(
            transcriptionEnabled: { true },
            automaticallyDrains: false
        )
        await coordinator.resumePending(root: root)

        #expect(await coordinator.queuedSessions().map(\.lastPathComponent) == [
            session.dir.lastPathComponent
        ])
        let metadata = try SessionMeta.read(from: session.dir)
        #expect(metadata.tracks.map(\.file) == ["system.caf"])
        #expect(metadata.tracks.map(\.speaker) == ["them"])
        #expect(metadata.tracks.map(\.offsetMs) == [0])
    }

    @Test func unreadableManifestLogIsPrivate() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-private-transcription-log-\(UUID().uuidString)", isDirectory: true)
        try PrivateFileSystem.createDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = root.appendingPathComponent("0000-unreadable", isDirectory: true)
        try PrivateFileSystem.createDirectory(session)
        try AtomicFileWriter.production.write(
            Data("not-json".utf8),
            to: session.appendingPathComponent("session.json")
        )

        let coordinator = TranscriptionCoordinator(
            transcriptionEnabled: { true },
            automaticallyDrains: false
        )
        await coordinator.resumePending(root: root)

        let log = session.appendingPathComponent("transcribe.log")
        #expect(FileManager.default.fileExists(atPath: log.path))
        #expect(try posixMode(of: log) == 0o600)
    }

    private func posixMode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int) & 0o777
    }
}
