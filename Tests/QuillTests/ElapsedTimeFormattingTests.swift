import Testing
@testable import quill

struct ElapsedTimeFormattingTests {
    @MainActor @Test func formatsSubhourIntervals() {
        #expect(AppController.format(0) == "0:00")
        #expect(AppController.format(59.9) == "0:59")
        #expect(AppController.format(60) == "1:00")
        #expect(AppController.format(3_599) == "59:59")
    }

    @MainActor @Test func formatsIntervalsWithHours() {
        #expect(AppController.format(3_600) == "1:00:00")
        #expect(AppController.format(7_445) == "2:04:05")
    }
}
