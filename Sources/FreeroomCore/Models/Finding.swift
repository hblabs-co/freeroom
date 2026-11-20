import Foundation

/// How safe it is to remove something.
public enum SafetyClass: String, Codable, CaseIterable, Sendable {
    /// Regenerable: caches, build output, downloads of things installed elsewhere.
    case safe
    /// User data or something that may still be in use. The user decides.
    case review
    /// System or important data. Freeroom never offers to delete it.
    case keep
}

/// Who produced a finding.
public enum FindingSource: String, Codable, Sendable {
    /// Built-in rule engine (no AI).
    case rule
    /// Reported by an agent through `freeroom report`.
    case agent
}

/// How the app should clean a finding once the user confirms.
public enum CleanupAction: String, Codable, Sendable {
    /// Run the tool's own cleanup command (`docker builder prune`, `go clean -modcache`…).
    case command
    /// Move to the Trash (default for `review`).
    case trash
    /// Delete permanently (default for regenerable `safe` items).
    case delete
    /// Nothing to do automatically; informational only.
    case none
}

public enum FindingCategory: String, Codable, CaseIterable, Sendable {
    case docker, xcode, appCaches, devCaches, projects, personal, apps, system, other

    public var title: String {
        switch self {
        case .docker: "Docker"
        case .xcode: "Xcode / iOS"
        case .appCaches: "App caches"
        case .devCaches: "Developer caches"
        case .projects: "Projects"
        case .personal: "Personal files"
        case .apps: "Applications"
        case .system: "System"
        case .other: "Other"
        }
    }
}

/// Evidence for a classification, so the UI can show *why* something is safe.
public struct Verification: Codable, Equatable, Sendable {
    /// Identifier of the rule that matched, e.g. `rust-target` or `catalog:spotify-cache`.
    public var rule: String
    /// Human-readable evidence, e.g. "Cargo.toml next to target/".
    public var evidence: String
    /// Whether Freeroom itself re-measured the paths (true) or only trusts the reporter (false).
    public var measuredByFreeroom: Bool

    public init(rule: String, evidence: String, measuredByFreeroom: Bool) {
        self.rule = rule
        self.evidence = evidence
        self.measuredByFreeroom = measuredByFreeroom
    }
}

/// One thing that could be cleaned. Schema version 1.
public struct Finding: Codable, Identifiable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schema: Int
    public var id: String
    public var title: String
    public var paths: [String]
    public var sizeBytes: Int64
    /// Bytes inside `paths` that belong to files with other hard links. Deleting may free less.
    public var sharedBytes: Int64
    public var safety: SafetyClass
    public var source: FindingSource
    public var category: FindingCategory
    /// Explanation in English (translation happens on demand, see ARCHITECTURE.md).
    public var explanation: String
    public var action: CleanupAction
    /// Exact command to run when `action == .command`.
    public var command: String?
    public var needsAdmin: Bool
    public var verification: Verification?
    public var scanId: String?
    /// How the app draws this finding (app icon, brand logo or SF Symbol).
    public var icon: IconRef?

    public init(
        id: String,
        title: String,
        paths: [String],
        sizeBytes: Int64,
        sharedBytes: Int64 = 0,
        safety: SafetyClass,
        source: FindingSource,
        category: FindingCategory,
        explanation: String,
        action: CleanupAction,
        command: String? = nil,
        needsAdmin: Bool = false,
        verification: Verification? = nil,
        scanId: String? = nil,
        icon: IconRef? = nil
    ) {
        self.schema = Finding.schemaVersion
        self.id = id
        self.title = title
        self.paths = paths
        self.sizeBytes = sizeBytes
        self.sharedBytes = sharedBytes
        self.safety = safety
        self.source = source
        self.category = category
        self.explanation = explanation
        self.action = action
        self.command = command
        self.needsAdmin = needsAdmin
        self.verification = verification
        self.scanId = scanId
        self.icon = icon
    }
}

public extension Int64 {
    /// "12.4 GB", "512 MB" — decimal units like Finder.
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
