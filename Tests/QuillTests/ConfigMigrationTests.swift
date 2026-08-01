import Foundation
import Testing
@testable import quill

struct ConfigMigrationTests {
    @Test func legacyOnStopKeyProducesAnActionableNoticeWithoutLeakingItsValue() {
        let secretCommand = "upload --token do-not-print"
        let config: [String: Any] = [
            "recordings_dir": "/keep-me",
            "on_stop": secretCommand,
        ]

        let notices = Config.migrationNotices(in: config)

        #expect(notices.count == 1)
        #expect(notices[0].title.contains("configuration update required"))
        #expect(notices[0].message.contains("on_stop"))
        #expect(notices[0].message.contains("no longer supported"))
        #expect(notices[0].message.contains("ignored"))
        #expect(notices[0].message.contains("Remove"))
        #expect(!notices[0].message.contains(secretCommand))
        #expect(config["recordings_dir"] as? String == "/keep-me")
    }

    @Test func anyLegacyOnStopValueProducesExactlyOneNotice() {
        let legacyValues: [Any] = ["", 42, NSNull()]

        for value in legacyValues {
            let notices = Config.migrationNotices(in: ["on_stop": value])
            #expect(notices.count == 1)
        }
    }

    @Test func configWithoutLegacyKeyProducesNoMigrationNotice() {
        let notices = Config.migrationNotices(in: [
            "recordings_dir": "/recordings",
            "transcription": ["enabled": false],
        ])

        #expect(notices.isEmpty)
    }
}
