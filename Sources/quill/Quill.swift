import AppKit
import ArgumentParser
import Foundation

/// Emits already-sanitized config migration notices through both channels.
/// The sinks are injectable so package tests can prove cardinality without
/// writing to a real stderr stream or launching a user notification.
func reportConfigMigrationNotices(
    _ notices: [ConfigMigrationNotice],
    writeWarning: (String) -> Void,
    showNotification: (String, String) -> Void
) {
    for notice in notices {
        writeWarning("warning: \(notice.message)\n")
        showNotification(notice.title, notice.message)
    }
}

@main
struct Quill: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quill",
        abstract: "Local meeting recorder + transcriber. Records mic and system audio as two tracks, then transcribes on-device.",
        subcommands: [Run.self, Doctor.self, Install.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the menu-bar daemon (default)."
    )

    @Option(name: .long, help: "Recordings root directory (overrides the config file).")
    var out: String?

    func run() throws {
        // ArgumentParser invokes run() on the main thread; promote that fact
        // to the type system so AppKit calls are cleanly isolated.
        try MainActor.assumeIsolated { try runMain() }
    }

    @MainActor
    private func runMain() throws {
        let root = Config.resolveRoot(cliOverride: out)
        reportConfigMigrationNotices(
            Config.migrationNotices(),
            writeWarning: { FileHandle.standardError.write(Data($0.utf8)) },
            showNotification: { title, message in
                notifyUser(title: title, body: message)
            }
        )

        // Non-blocking: permissions prompt on first recording, so warnings at
        // startup are informational, not fatal.
        let checks = DoctorReport.run(recordingsRoot: root)
        if !DoctorReport.allOK(checks) {
            FileHandle.standardError.write(Data("startup checks failed:\n".utf8))
            DoctorReport.print(checks)
            throw ExitCode(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let controller = AppController(root: root)

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            FileHandle.standardError.write(Data("\nshutting down\n".utf8))
            MainActor.assumeIsolated { controller.shutdown() }
        }
        sigint.resume()
        signal(SIGINT, SIG_IGN)

        FileHandle.standardError.write(Data(
            "quill up · recordings → \(root.path) · ^C to quit\n".utf8
        ))
        app.run()
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check microphone, system audio, and recordings folder."
    )

    func run() throws {
        let checks = DoctorReport.run(recordingsRoot: Config.resolveRoot(cliOverride: nil))
        DoctorReport.print(checks)
        if !DoctorReport.allOK(checks) {
            throw ExitCode(1)
        }
    }
}

/// Owns the menu bar, the current recording session, and the elapsed-time
/// ticker. All state transitions happen on the main actor.
@MainActor
final class AppController {
    private let root: URL
    private let menuBar = MenuBarController()
    private let transcription = TranscriptionCoordinator()
    private var session: RecordingSessionSnapshot?
    private var sessionController: RecordingSessionController?
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var quitAfterCurrentOperation = false
    private var ticker: Timer?

    init(root: URL) {
        self.root = root
        menuBar.onToggle = { [weak self] in self?.toggle() }
        menuBar.onOpenFolder = { [weak self] in self?.openFolder() }
        menuBar.onQuit = { [weak self] in self?.shutdown() }
        menuBar.update(recording: false, elapsed: nil)

        do {
            let report = try SessionLifecycleRecovery(
                now: Date.init,
                atomicWriter: .production
            ).recover(in: root)
            if !report.recovered.isEmpty {
                FileHandle.standardError.write(Data(
                    "recovered \(report.recovered.count) interrupted recording(s)\n".utf8
                ))
            }
            for failure in report.failures {
                FileHandle.standardError.write(Data(
                    "recording recovery skipped \(failure.directory.path): \(failure.kind)\n".utf8
                ))
            }
        } catch {
            FileHandle.standardError.write(Data(
                "recording recovery failed: \(error)\n".utf8
            ))
            notifyUser(
                title: "quill — recording recovery failed",
                body: "Some interrupted recordings could not be classified. \(error)"
            )
        }

        Task { [transcription, root] in
            await transcription.setStatusHandler { status in
                Task { @MainActor [weak self] in
                    self?.showTranscription(status)
                }
            }
            await transcription.resumePending(root: root)
        }
    }

    /// Stop any live session cleanly (finalizing files) and exit.
    func shutdown() {
        if startTask != nil || stopTask != nil {
            quitAfterCurrentOperation = true
        } else if session != nil {
            stopSession(terminateAfter: true)
        } else {
            NSApp.terminate(nil)
        }
    }

    private func toggle() {
        guard startTask == nil, stopTask == nil else { return }
        if session == nil {
            startSession()
        } else {
            stopSession()
        }
    }

    private func startSession() {
        let controller = RecordingSessionController(root: root)
        sessionController = controller
        startTask = Task { [weak self] in
            do {
                let snapshot = try await controller.start()
                guard let self else {
                    _ = try? await controller.stop()
                    return
                }
                self.startTask = nil
                self.session = snapshot
                FileHandle.standardError.write(Data(
                    "● recording → \(snapshot.directory.path)\n".utf8
                ))
                self.menuBar.update(recording: true, elapsed: "0:00")
                self.ticker = Timer.scheduledTimer(
                    withTimeInterval: 1,
                    repeats: true
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
                if self.quitAfterCurrentOperation {
                    self.stopSession(terminateAfter: true)
                }
            } catch {
                guard let self else { return }
                self.startTask = nil
                self.sessionController = nil
                FileHandle.standardError.write(Data("recording start failed: \(error)\n".utf8))
                notifyUser(title: "quill — recording failed", body: "\(error)")
                if self.quitAfterCurrentOperation {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func stopSession(terminateAfter: Bool = false) {
        guard let session, let controller = sessionController else {
            if terminateAfter { NSApp.terminate(nil) }
            return
        }
        let elapsed = Self.format(Date().timeIntervalSince(session.startedAt))
        self.session = nil
        self.sessionController = nil
        ticker?.invalidate()
        ticker = nil
        menuBar.update(recording: false, elapsed: nil)
        stopTask = Task { [weak self, transcription] in
            do {
                _ = try await controller.stop()
                FileHandle.standardError.write(Data(
                    "○ stopped · \(elapsed) · \(session.directory.path)\n".utf8
                ))
                await transcription.enqueue(session.directory)
            } catch {
                FileHandle.standardError.write(Data(
                    "recording finalization failed: \(error)\n".utf8
                ))
                notifyUser(title: "quill — recording finalization failed", body: "\(error)")
            }
            let shouldTerminate = terminateAfter || self?.quitAfterCurrentOperation == true
            self?.stopTask = nil
            if shouldTerminate {
                NSApp.terminate(nil)
            }
        }
    }

    private func showTranscription(_ status: TranscriptionCoordinator.Status) {
        switch status {
        case .idle:
            menuBar.updateTranscription(nil)
        case .transcribing(let name, let queued):
            menuBar.updateTranscription(
                queued > 0 ? "transcribing \(name) · \(queued) queued" : "transcribing \(name)"
            )
        case .failed(let name):
            menuBar.updateTranscription("transcription failed · \(name)")
        }
    }

    private func tick() {
        guard let session else { return }
        menuBar.update(
            recording: true,
            elapsed: Self.format(Date().timeIntervalSince(session.startedAt))
        )
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    /// Internal so package tests can preserve the menu's legacy clock format.
    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
