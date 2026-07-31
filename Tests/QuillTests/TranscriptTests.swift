import Foundation
import Testing
@testable import quill

struct TranscriptTests {
    @Test func writesCanonicalJSONAndReadableMarkdown() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("2026.07.31-1030-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let transcript = Transcript(
            engine: "parakeet",
            model: "fixture-model",
            created_at: "2026-07-31T15:30:00Z",
            segments: [
                .init(speaker: "me", start_ms: 61_000, end_ms: 62_000, text: "First line."),
                .init(speaker: "them", start_ms: 3_661_000, end_ms: 3_662_000, text: "Second line."),
            ]
        )

        try transcript.write(to: directory)

        let jsonURL = directory.appendingPathComponent("transcript.json")
        let decoded = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: jsonURL))
        #expect(decoded.engine == "parakeet")
        #expect(decoded.model == "fixture-model")
        #expect(decoded.created_at == "2026-07-31T15:30:00Z")
        #expect(decoded.segments.count == 2)
        #expect(decoded.segments[0].speaker == "me")
        #expect(decoded.segments[0].start_ms == 61_000)
        #expect(decoded.segments[0].end_ms == 62_000)
        #expect(decoded.segments[0].text == "First line.")

        let markdown = try String(
            contentsOf: directory.appendingPathComponent("transcript.md"),
            encoding: .utf8
        )
        #expect(
            markdown == """
            # \(directory.lastPathComponent)

            engine: parakeet (fixture-model)

            **[1:01] me:** First line.

            **[1:01:01] them:** Second line.

            """
        )
    }
}
