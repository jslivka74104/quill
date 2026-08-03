import Darwin
import Foundation

enum RecordingRootCapability: String, CaseIterable, Sendable {
    case localWritableVolume = "local_writable_volume"
    case privacySafeLocation = "privacy_safe_location"
    case privatePermissions = "private_permissions"
    case atomicReplacement = "atomic_replacement"
    case fileAndDirectorySync = "file_and_directory_sync"
    case capacityReserve = "capacity_reserve"
}

struct RecordingRootPreflightError: Error, Equatable, Sendable, CustomStringConvertible {
    let capability: RecordingRootCapability
    let fileSystem: String
    let context: FailureContext

    var description: String {
        "recording root failed \(capability.rawValue) on \(fileSystem): \(context.message)"
    }
}

/// Ordered, injectable recording-root capability validation. The production
/// probe performs real local filesystem operations; tests replace only the
/// probe while retaining the same fail-before-evidence ordering.
struct RecordingRootPreflight {
    private let fileSystemName: (URL) -> String
    private let probe: (RecordingRootCapability, URL) throws -> Void

    init(
        fileSystemName: @escaping (URL) -> String,
        probe: @escaping (RecordingRootCapability, URL) throws -> Void
    ) {
        self.fileSystemName = fileSystemName
        self.probe = probe
    }

    func validate(_ root: URL) throws {
        let fileSystem = fileSystemName(root)
        for capability in RecordingRootCapability.allCases {
            do {
                try probe(capability, root)
            } catch let error as RecordingRootPreflightError {
                throw error
            } catch {
                throw RecordingRootPreflightError(
                    capability: capability,
                    fileSystem: fileSystem,
                    context: FailureContext(error)
                )
            }
        }
    }

    static func production(
        minimumAvailableCapacityBytes: Int64 = 1_073_741_824
    ) -> RecordingRootPreflight {
        RecordingRootPreflight(
            fileSystemName: { root in
                (try? fileSystemType(at: root)) ?? "unknown"
            },
            probe: { capability, root in
                switch capability {
                case .localWritableVolume:
                    try verifyLocalWritableAPFS(root)
                case .privacySafeLocation:
                    try verifyPrivacySafeLocation(root)
                case .privatePermissions:
                    try verifyPrivatePermissions(root)
                case .atomicReplacement:
                    try verifyAtomicReplacement(root)
                case .fileAndDirectorySync:
                    try verifyFileAndDirectorySync(root)
                case .capacityReserve:
                    try verifyCapacity(root, minimumBytes: minimumAvailableCapacityBytes)
                }
            }
        )
    }

    private static func verifyLocalWritableAPFS(_ root: URL) throws {
        let values = try root.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsReadOnlyKey])
        guard values.volumeIsLocal == true else {
            throw CapabilityProbeError("volume is not local")
        }
        guard values.volumeIsReadOnly == false, FileManager.default.isWritableFile(atPath: root.path) else {
            throw CapabilityProbeError("volume or recording root is not writable")
        }
        let type = try fileSystemType(at: root)
        guard type.caseInsensitiveCompare("apfs") == .orderedSame else {
            throw CapabilityProbeError("unsupported filesystem \(type); live recording requires APFS")
        }
    }

    private static func verifyPrivacySafeLocation(_ root: URL) throws {
        let standardized = root.standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [.isUbiquitousItemKey])
        guard values.isUbiquitousItem != true else {
            throw CapabilityProbeError("root is managed by iCloud")
        }

        let path = standardized.path
        let cloudMarkers = [
            "/Library/Mobile Documents/",
            "/Library/CloudStorage/",
            "/Mobile Documents/",
        ]
        guard !cloudMarkers.contains(where: path.contains) else {
            throw CapabilityProbeError("root is inside a File Provider or cloud-managed location")
        }
    }

    private static func verifyPrivatePermissions(_ root: URL) throws {
        try withProbeDirectory(in: root) { directory in
            try PrivateFileSystem.verifyMode(of: directory, expected: 0o700)
            let file = directory.appendingPathComponent("mode-probe")
            guard FileManager.default.createFile(
                atPath: file.path,
                contents: Data(),
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CapabilityProbeError("could not create permission probe file")
            }
            try PrivateFileSystem.verifyMode(of: file, expected: 0o600)
        }
    }

    private static func verifyAtomicReplacement(_ root: URL) throws {
        try withProbeDirectory(in: root) { directory in
            let target = directory.appendingPathComponent("replace-target")
            let replacement = directory.appendingPathComponent("replace-source")
            try createProbeFile(Data("old".utf8), at: target)
            try createProbeFile(Data("new".utf8), at: replacement)

            guard Darwin.rename(replacement.path, target.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard try Data(contentsOf: target) == Data("new".utf8) else {
                throw CapabilityProbeError("same-directory replacement did not publish the new bytes")
            }
        }
    }

    private static func verifyFileAndDirectorySync(_ root: URL) throws {
        try withProbeDirectory(in: root) { directory in
            let file = directory.appendingPathComponent("sync-probe")
            try createProbeFile(Data("sync".utf8), at: file)
            let handle = try FileHandle(forWritingTo: file)
            try handle.synchronize()
            try handle.close()
            try PrivateFileSystem.synchronizeDirectory(directory)
        }
    }

    private static func verifyCapacity(_ root: URL, minimumBytes: Int64) throws {
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let fileSystemAttributes = try FileManager.default.attributesOfFileSystem(forPath: root.path)
        let generalAvailable = (fileSystemAttributes[.systemFreeSize] as? NSNumber)?.int64Value
        guard let available = [values.volumeAvailableCapacityForImportantUsage, generalAvailable]
            .compactMap({ $0 })
            .max()
        else {
            throw CapabilityProbeError("available recording capacity could not be determined")
        }
        guard available >= minimumBytes else {
            throw CapabilityProbeError(
                "available capacity \(available) bytes is below the \(minimumBytes)-byte reserve"
            )
        }
    }

    private static func withProbeDirectory(
        in root: URL,
        operation: (URL) throws -> Void
    ) throws {
        let directory = root.appendingPathComponent(
            ".quill-preflight-\(UUID().uuidString)",
            isDirectory: true
        )
        try PrivateFileSystem.createDirectory(directory)

        do {
            try operation(directory)
        } catch {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                // The capability error remains authoritative; the abandoned
                // random probe directory contains no interview evidence.
            }
            throw error
        }
        try FileManager.default.removeItem(at: directory)
    }

    private static func createProbeFile(_ data: Data, at url: URL) throws {
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CapabilityProbeError("could not create probe file")
        }
        try PrivateFileSystem.verifyMode(of: url, expected: 0o600)
    }

    private static func fileSystemType(at root: URL) throws -> String {
        let values = try root.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey])
        guard let description = values.volumeLocalizedFormatDescription, !description.isEmpty else {
            throw CapabilityProbeError("filesystem type could not be determined")
        }
        return description.localizedCaseInsensitiveContains("apfs") ? "apfs" : description
    }

    private struct CapabilityProbeError: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }
}

enum PrivateFileSystem {
    static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try verifyMode(of: url, expected: 0o700)
    }

    static func verifyMode(of url: URL, expected: Int) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let actual = attributes[.posixPermissions] as? Int else {
            throw PrivateFileSystemError.modeUnavailable(url)
        }
        guard actual & 0o777 == expected else {
            throw PrivateFileSystemError.unexpectedMode(
                url,
                expected: expected,
                actual: actual & 0o777
            )
        }
    }

    static func preparePrivateFile(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw PrivateFileSystemError.cannotCreateFile(url)
            }
        }
        try securePrivateFile(url)
    }

    static func securePrivateFile(_ url: URL) throws {
        let result = url.path.withCString { path in
            Darwin.chmod(path, mode_t(0o600))
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try verifyMode(of: url, expected: 0o600)
    }

    static func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = Darwin.open(directory.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    enum PrivateFileSystemError: Error, CustomStringConvertible {
        case cannotCreateFile(URL)
        case modeUnavailable(URL)
        case unexpectedMode(URL, expected: Int, actual: Int)

        var description: String {
            switch self {
            case .cannotCreateFile(let url):
                return "could not create private file \(url.path)"
            case .modeUnavailable(let url):
                return "POSIX mode is unavailable for \(url.path)"
            case .unexpectedMode(let url, let expected, let actual):
                return "\(url.path) has mode \(String(actual, radix: 8)); expected \(String(expected, radix: 8))"
            }
        }
    }
}
