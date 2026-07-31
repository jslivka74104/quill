import Foundation
import Testing
@testable import quill

struct ConfigTests {
    @Test func resolveRootPrefersCLIOverride() {
        let configured = URL(fileURLWithPath: "/configured", isDirectory: true)
        let fallback = URL(fileURLWithPath: "/default", isDirectory: true)

        let resolved = Config.resolveRoot(
            cliOverride: "/cli",
            configured: configured,
            defaultRoot: fallback
        )

        #expect(resolved.path == "/cli")
    }

    @Test func cliOverrideDoesNotReadConfiguredRoot() {
        var didReadConfiguredRoot = false
        let fallback = URL(fileURLWithPath: "/default", isDirectory: true)

        func configuredRoot() -> URL? {
            didReadConfiguredRoot = true
            return URL(fileURLWithPath: "/configured", isDirectory: true)
        }

        let resolved = Config.resolveRoot(
            cliOverride: "/cli",
            configured: configuredRoot(),
            defaultRoot: fallback
        )

        #expect(resolved.path == "/cli")
        #expect(didReadConfiguredRoot == false)
    }

    @Test func resolveRootUsesConfiguredRootWithoutCLIOverride() {
        let configured = URL(fileURLWithPath: "/configured", isDirectory: true)
        let fallback = URL(fileURLWithPath: "/default", isDirectory: true)

        let resolved = Config.resolveRoot(
            cliOverride: nil,
            configured: configured,
            defaultRoot: fallback
        )

        #expect(resolved == configured)
    }

    @Test func resolveRootUsesDefaultWithoutOverrides() {
        let fallback = URL(fileURLWithPath: "/default", isDirectory: true)

        let resolved = Config.resolveRoot(
            cliOverride: nil,
            configured: nil,
            defaultRoot: fallback
        )

        #expect(resolved == fallback)
    }

    @Test func resolveRootExpandsTildeInCLIOverride() {
        let fallback = URL(fileURLWithPath: "/default", isDirectory: true)

        let resolved = Config.resolveRoot(
            cliOverride: "~/Quill Tests",
            configured: nil,
            defaultRoot: fallback
        )

        #expect(
            resolved.path
                == FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Quill Tests", isDirectory: true).path
        )
    }
}
