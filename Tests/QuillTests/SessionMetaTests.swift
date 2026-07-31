import Foundation
import Testing
@testable import quill

struct SessionMetaTests {
    @Test func readsTwoTrackMetadataAndOffsets() throws {
        let directory = try makeSessionDirectory(meta: """
        {
          "files": { "mic": "mic.caf", "system": "system.caf" },
          "start_offset_ms": { "mic": 27, "system": 0 }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }

        let meta = try SessionMeta.read(from: directory)

        #expect(meta.tracks.count == 2)
        #expect(meta.tracks[0].file == "mic.caf")
        #expect(meta.tracks[0].speaker == "me")
        #expect(meta.tracks[0].offsetMs == 27)
        #expect(meta.tracks[1].file == "system.caf")
        #expect(meta.tracks[1].speaker == "them")
        #expect(meta.tracks[1].offsetMs == 0)
    }

    @Test func defaultsMissingLegacyOffsetsToZero() throws {
        let directory = try makeSessionDirectory(meta: """
        { "files": { "mic": "mic.caf", "system": "system.caf" } }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }

        let meta = try SessionMeta.read(from: directory)

        #expect(meta.tracks.map(\.offsetMs) == [0, 0])
    }

    @Test func rejectsUnreadableMetadataWithFileContext() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not json".utf8).write(to: directory.appendingPathComponent("meta.json"))

        let error = #expect(throws: SessionMeta.MetaError.self) {
            try SessionMeta.read(from: directory)
        }
        #expect(
            String(describing: error)
                == "can't parse \(directory.appendingPathComponent("meta.json").path)"
        )
    }

    private func makeSessionDirectory(meta: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(meta.utf8).write(to: directory.appendingPathComponent("meta.json"))
        return directory
    }
}
