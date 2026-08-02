import Foundation

/// Optional user config at ~/.config/quill/config.json:
///
///     {
///       "recordings_dir": "~/Recordings",
///       "transcription": { "enabled": true, "engine": "parakeet" },
///       "mic_voice_processing": true
///     }
///
/// Resolution order for the recordings root: --out flag > config file >
/// ~/Recordings.
struct ConfigMigrationNotice: Equatable, Sendable {
    let title: String
    let message: String
}

enum Config {
    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/quill/config.json")

    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Recordings", isDirectory: true)

    /// The configured recordings root, or nil if no config file / no key.
    static func recordingsDir() -> URL? {
        guard let dir = load()?["recordings_dir"] as? String, !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Notices for removed settings in the user's current config. This is
    /// called once by the application startup path, so a legacy key produces
    /// one notice per process launch without changing the later config reads.
    static func migrationNotices() -> [ConfigMigrationNotice] {
        migrationNotices(at: path, writeWarning: writeConfigWarning)
    }

    /// File-backed seam used by package tests to exercise the same loading and
    /// malformed-config behavior as application startup without touching the
    /// user's real config file.
    static func migrationNotices(
        at configURL: URL,
        writeWarning: (String) -> Void
    ) -> [ConfigMigrationNotice] {
        guard let config = load(from: configURL, writeWarning: writeWarning) else { return [] }
        return migrationNotices(in: config)
    }

    /// Pure warning seam for package tests. Presence of the legacy key is
    /// enough to warn: its value is intentionally ignored and never rendered.
    static func migrationNotices(in config: [String: Any]) -> [ConfigMigrationNotice] {
        guard config.keys.contains("on_stop") else { return [] }
        return [
            ConfigMigrationNotice(
                title: "quill — configuration update required",
                message: "The \"on_stop\" setting is no longer supported and was ignored. "
                    + "Remove it from ~/.config/quill/config.json. "
                    + "Quill no longer runs commands after recording."
            ),
        ]
    }

    /// Whether finished recordings are transcribed automatically. Default on.
    static func transcriptionEnabled() -> Bool {
        transcription()?["enabled"] as? Bool ?? true
    }

    /// Configured engine name. Only "parakeet" ships today; the coordinator
    /// warns and falls back for anything else.
    static func transcriptionEngine() -> String {
        transcription()?["engine"] as? String ?? "parakeet"
    }

    private static func transcription() -> [String: Any]? {
        load()?["transcription"] as? [String: Any]
    }

    /// Apple voice processing (acoustic echo cancellation) on the mic, so
    /// speaker playback doesn't bleed into the mic track and get transcribed
    /// as "me". Default off — the live voice unit ducks all other playback,
    /// and on headphones there's no echo to cancel anyway. Set true when
    /// recording meetings through the speakers.
    static func micVoiceProcessing() -> Bool {
        load()?["mic_voice_processing"] as? Bool ?? false
    }

    /// Parse the config file. A malformed config is reported on stderr rather
    /// than silently ignored — recordings landing in an unexpected place is
    /// worse than a warning.
    private static func load() -> [String: Any]? {
        load(from: path, writeWarning: writeConfigWarning)
    }

    private static func load(
        from configURL: URL,
        writeWarning: (String) -> Void
    ) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
        guard
            let data = try? Data(contentsOf: configURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            writeWarning("warning: \(configURL.path) is not valid JSON — ignoring config\n")
            return nil
        }
        return json
    }

    private static func writeConfigWarning(_ warning: String) {
        FileHandle.standardError.write(Data(warning.utf8))
    }

    /// Resolve the recordings root from an optional CLI override.
    static func resolveRoot(cliOverride: String?) -> URL {
        resolveRoot(
            cliOverride: cliOverride,
            configured: recordingsDir(),
            defaultRoot: defaultRoot
        )
    }

    /// Pure precedence seam used by the package tests. Keeping filesystem
    /// config loading at the caller preserves the existing runtime behavior.
    static func resolveRoot(
        cliOverride: String?,
        configured: @autoclosure () -> URL?,
        defaultRoot: URL
    ) -> URL {
        if let cliOverride {
            return URL(
                fileURLWithPath: (cliOverride as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }
        return configured() ?? defaultRoot
    }
}
