import FluidAudio
import Testing
@testable import quill

struct ParakeetSegmentationTests {
    @Test func returnsNoSegmentsForNoWords() {
        #expect(ParakeetEngine.segments(from: []).isEmpty)
    }

    @Test func splitsAfterSentencePunctuationAndPreservesBounds() throws {
        let segments = ParakeetEngine.segments(from: [
            word("Hello", start: 0, end: 0.2),
            word("world.", start: 0.2, end: 0.5),
            word("Next", start: 0.5, end: 0.8),
        ])

        #expect(segments.count == 2)
        let first = try #require(segments.first)
        #expect(first.start == 0)
        #expect(first.end == 0.5)
        #expect(first.text == "Hello world.")
        #expect(segments[1].text == "Next")
    }

    @Test func splitsOnlyWhenSilenceExceedsOneSecond() {
        let segments = ParakeetEngine.segments(from: [
            word("Exact", start: 0, end: 0.5),
            word("threshold", start: 1.5, end: 1.7),
            word("Beyond", start: 2.701, end: 2.9),
        ])

        #expect(segments.count == 2)
        #expect(segments[0].text == "Exact threshold")
        #expect(segments[1].text == "Beyond")
    }

    @Test func capsRunOnSpeechAtSixtyWords() {
        let words = (0..<61).map { index in
            word("w\(index)", start: Double(index) * 0.1, end: Double(index + 1) * 0.1)
        }

        let segments = ParakeetEngine.segments(from: words)

        #expect(segments.count == 2)
        #expect(segments[0].text.split(separator: " ").count == 60)
        #expect(segments[1].text == "w60")
    }

    private func word(_ text: String, start: Double, end: Double) -> WordTiming {
        WordTiming(word: text, startTime: start, endTime: end)
    }
}
