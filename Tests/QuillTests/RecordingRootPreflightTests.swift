import Foundation
import Testing
@testable import quill

struct RecordingRootPreflightTests {
    @Test(arguments: RecordingRootCapability.allCases)
    func refusesEachCapabilityFailureBeforeCreatingEvidence(
        capability: RecordingRootCapability
    ) throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let preflight = RecordingRootPreflight(
            fileSystemName: { _ in "fixturefs" },
            probe: { attempted, _ in
                if attempted == capability {
                    throw FixtureFailure.rejected
                }
            }
        )
        let dependencies = RecordingSession.Dependencies.testing(
            preflight: preflight,
            recorders: makeLiveRecorders()
        )

        let error = try #require(throws: RecordingRootPreflightError.self) {
            _ = try RecordingSession(root: root, dependencies: dependencies)
        }

        #expect(error.capability == capability)
        #expect(error.fileSystem == "fixturefs")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func productionStorageCreatesAndVerifiesPrivateModes() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let dependencies = RecordingSession.Dependencies.testing(
            preflight: .production(),
            recorders: makeLiveRecorders()
        )
        let session = try RecordingSession(root: root, dependencies: dependencies)

        #expect(try posixMode(of: session.dir) == 0o700)
        #expect(try posixMode(of: session.dir.appendingPathComponent("session.json")) == 0o600)
    }

    private enum FixtureFailure: Error {
        case rejected
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-preflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    private func posixMode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    private func makeLiveRecorders() -> [RecordingTrackDriver] {
        let firstSample = Date(timeIntervalSince1970: 1_700_000_001)
        return [
            .fixtureSystem(firstSampleAt: { firstSample }),
            .fixtureMicrophone(firstSampleAt: { firstSample }),
        ]
    }
}
