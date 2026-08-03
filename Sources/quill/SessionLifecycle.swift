import Foundation

struct FailureContext: Equatable, Sendable, Codable {
    let domain: String
    let code: Int
    let message: String

    init(_ error: Error) {
        let error = error as NSError
        domain = error.domain
        code = error.code
        message = String(describing: error)
    }
}

enum SessionLifecycleState: String, Codable, Equatable, Sendable {
    case starting
    case recording
    case complete
    case interrupted
    case failed

    var isTerminal: Bool {
        self == .complete || self == .interrupted || self == .failed
    }
}

enum CaptureProfile: String, Codable, Equatable, Sendable {
    case onlineMeeting = "online_meeting"
}

enum SessionTrackRole: String, Codable, Equatable, Sendable {
    case microphone
    case system
}

enum SessionTrackCriticality: String, Codable, Equatable, Sendable {
    case primary
    case secondary
}

enum SessionTrackCaptureStatus: String, Codable, Equatable, Sendable {
    case pending
    case recording
    case complete
    case degraded
    case interrupted
    case missing
    case invalid
}

enum SessionFailurePhase: String, Codable, Equatable, Sendable {
    case starting
    case capture
    case finalization
    case storage
}

struct SessionFailure: Codable, Equatable, Sendable {
    let code: String
    let phase: SessionFailurePhase
    let message: String
    let observedAt: Date

    private enum CodingKeys: String, CodingKey {
        case code
        case phase
        case message
        case observedAt = "observed_at"
    }
}

struct SessionTrackFailure: Codable, Equatable, Sendable {
    let code: String
    let message: String
    let observedAt: Date
    let recoveryAttempted: Bool

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case observedAt = "observed_at"
        case recoveryAttempted = "recovery_attempted"
    }
}

struct SessionTimebase: Codable, Equatable, Sendable {
    let unit: String
    let origin: String

    init(
        unit: String = "milliseconds",
        origin: String = "earliest_track_first_sample"
    ) {
        self.unit = unit
        self.origin = origin
    }
}

struct SessionTrack: Codable, Equatable, Sendable {
    let trackID: String
    let partID: String
    let role: SessionTrackRole
    let criticality: SessionTrackCriticality
    let relativePath: String
    let mediaType: String
    var startOffsetMs: Int?
    var durationMs: Int?
    var captureStatus: SessionTrackCaptureStatus
    var failure: SessionTrackFailure?
    var byteCount: Int
    var sha256: String?

    private enum CodingKeys: String, CodingKey {
        case trackID = "track_id"
        case partID = "part_id"
        case role
        case criticality
        case relativePath = "relative_path"
        case mediaType = "media_type"
        case startOffsetMs = "start_offset_ms"
        case durationMs = "duration_ms"
        case captureStatus = "capture_status"
        case failure
        case byteCount = "byte_count"
        case sha256
    }

    init(
        trackID: String,
        partID: String,
        role: SessionTrackRole,
        criticality: SessionTrackCriticality,
        relativePath: String,
        mediaType: String,
        startOffsetMs: Int? = nil,
        durationMs: Int? = nil,
        captureStatus: SessionTrackCaptureStatus = .pending,
        failure: SessionTrackFailure? = nil,
        byteCount: Int = 0,
        sha256: String? = nil
    ) {
        self.trackID = trackID
        self.partID = partID
        self.role = role
        self.criticality = criticality
        self.relativePath = relativePath
        self.mediaType = mediaType
        self.startOffsetMs = startOffsetMs
        self.durationMs = durationMs
        self.captureStatus = captureStatus
        self.failure = failure
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackID = try container.decode(String.self, forKey: .trackID)
        partID = try container.decode(String.self, forKey: .partID)
        role = try container.decode(SessionTrackRole.self, forKey: .role)
        criticality = try container.decode(SessionTrackCriticality.self, forKey: .criticality)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        startOffsetMs = try container.decodeIfPresent(Int.self, forKey: .startOffsetMs)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        captureStatus = try container.decode(SessionTrackCaptureStatus.self, forKey: .captureStatus)
        failure = try container.decodeIfPresent(SessionTrackFailure.self, forKey: .failure)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trackID, forKey: .trackID)
        try container.encode(partID, forKey: .partID)
        try container.encode(role, forKey: .role)
        try container.encode(criticality, forKey: .criticality)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(mediaType, forKey: .mediaType)
        if let startOffsetMs {
            try container.encode(startOffsetMs, forKey: .startOffsetMs)
        } else {
            try container.encodeNil(forKey: .startOffsetMs)
        }
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
        try container.encode(captureStatus, forKey: .captureStatus)
        if let failure {
            try container.encode(failure, forKey: .failure)
        } else {
            try container.encodeNil(forKey: .failure)
        }
        try container.encode(byteCount, forKey: .byteCount)
        if let sha256 {
            try container.encode(sha256, forKey: .sha256)
        } else {
            try container.encodeNil(forKey: .sha256)
        }
    }
}

struct SessionManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    var revision: Int
    let sessionID: UUID
    let captureProfile: CaptureProfile
    let capturePartID: String
    var state: SessionLifecycleState
    var failure: SessionFailure?
    let createdAt: Date
    var startedAt: Date?
    var endedAt: Date?
    var durationMs: Int?
    let timebase: SessionTimebase
    var tracks: [SessionTrack]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case revision
        case sessionID = "session_id"
        case captureProfile = "capture_profile"
        case capturePartID = "capture_part_id"
        case state
        case failure
        case createdAt = "created_at"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMs = "duration_ms"
        case timebase
        case tracks
    }

    init(
        sessionID: UUID,
        createdAt: Date,
        tracks: [SessionTrack]
    ) {
        schemaVersion = 2
        revision = 0
        self.sessionID = sessionID
        captureProfile = .onlineMeeting
        capturePartID = "part-0001"
        state = .starting
        failure = nil
        self.createdAt = createdAt
        startedAt = nil
        endedAt = nil
        durationMs = nil
        timebase = SessionTimebase()
        self.tracks = tracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        revision = try container.decode(Int.self, forKey: .revision)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        captureProfile = try container.decode(CaptureProfile.self, forKey: .captureProfile)
        capturePartID = try container.decode(String.self, forKey: .capturePartID)
        state = try container.decode(SessionLifecycleState.self, forKey: .state)
        failure = try container.decodeIfPresent(SessionFailure.self, forKey: .failure)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        timebase = try container.decode(SessionTimebase.self, forKey: .timebase)
        tracks = try container.decode([SessionTrack].self, forKey: .tracks)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(revision, forKey: .revision)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(captureProfile, forKey: .captureProfile)
        try container.encode(capturePartID, forKey: .capturePartID)
        try container.encode(state, forKey: .state)
        if let failure {
            try container.encode(failure, forKey: .failure)
        } else {
            try container.encodeNil(forKey: .failure)
        }
        try container.encode(createdAt, forKey: .createdAt)
        if let startedAt {
            try container.encode(startedAt, forKey: .startedAt)
        } else {
            try container.encodeNil(forKey: .startedAt)
        }
        if let endedAt {
            try container.encode(endedAt, forKey: .endedAt)
        } else {
            try container.encodeNil(forKey: .endedAt)
        }
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
        try container.encode(timebase, forKey: .timebase)
        try container.encode(tracks, forKey: .tracks)
    }
}

extension JSONEncoder {
    static var quill: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var quill: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct AtomicFileWriter {
    private let operation: (Data, URL) throws -> Void

    init(_ operation: @escaping (Data, URL) throws -> Void) {
        self.operation = operation
    }

    func write(_ data: Data, to destination: URL) throws {
        try operation(data, destination)
    }

    static var production: AtomicFileWriter {
        AtomicFileWriter { data, destination in
            let parent = destination.deletingLastPathComponent()
            let temporary = parent.appendingPathComponent(
                ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
            )
            guard FileManager.default.createFile(
                atPath: temporary.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw AtomicFileWriterError.cannotCreateTemporaryFile(temporary)
            }

            do {
                try PrivateFileSystem.verifyMode(of: temporary, expected: 0o600)
                let handle = try FileHandle(forWritingTo: temporary)
                do {
                    try handle.write(contentsOf: data)
                    try handle.synchronize()
                    try handle.close()
                } catch {
                    do { try handle.close() } catch { }
                    throw error
                }

                try PrivateFileSystem.replaceItem(at: temporary, with: destination)
                try PrivateFileSystem.verifyMode(of: destination, expected: 0o600)
                try PrivateFileSystem.synchronizeDirectory(parent)
            } catch {
                if FileManager.default.fileExists(atPath: temporary.path) {
                    do { try FileManager.default.removeItem(at: temporary) } catch { }
                }
                throw error
            }
        }
    }

    private enum AtomicFileWriterError: Error, CustomStringConvertible {
        case cannotCreateTemporaryFile(URL)

        var description: String {
            switch self {
            case .cannotCreateTemporaryFile(let url):
                return "could not create atomic-write sibling \(url.path)"
            }
        }
    }
}

struct SessionLifecycleRecovery {
    let now: () -> Date
    let atomicWriter: AtomicFileWriter

    func recover(in root: URL) throws -> [URL] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var recovered: [URL] = []

        for directory in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            let manifestURL = directory.appendingPathComponent("session.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }

            let data = try Data(contentsOf: manifestURL)
            var manifest = try JSONDecoder.quill.decode(SessionManifest.self, from: data)
            guard manifest.state == .starting || manifest.state == .recording else { continue }

            manifest.revision += 1
            manifest.state = .interrupted
            manifest.failure = nil
            manifest.endedAt = now()
            for index in manifest.tracks.indices {
                if manifest.tracks[index].captureStatus == .pending
                    || manifest.tracks[index].captureStatus == .recording
                {
                    manifest.tracks[index].captureStatus = .interrupted
                }
            }
            try atomicWriter.write(try JSONEncoder.quill.encode(manifest), to: manifestURL)
            recovered.append(directory)
        }
        return recovered
    }
}

enum SessionTranscriptionEligibility {
    /// Legacy folders without a v2 manifest retain their existing behavior.
    /// Once `session.json` exists, only the live process's durable `complete`
    /// transition authorizes the legacy transcription queue.
    static func allowsTranscription(in directory: URL) throws -> Bool {
        let manifestURL = directory.appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return true }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder.quill.decode(SessionManifest.self, from: data).state == .complete
    }
}
