import Foundation

/// How to draw a finding's icon, in order of preference:
/// the installed app's own icon, an official brand logo (Simple Icons, CC0), an SF Symbol.
public struct FindingIcon: Codable, Equatable, Hashable, Sendable {
    /// Bundle identifier of the app whose icon to show (resolved with NSWorkspace at runtime).
    public var app: String?
    /// Simple Icons slug (bundled SVG).
    public var brand: String?
    /// SF Symbol name; always present as the fallback.
    public var symbol: String

    public init(app: String? = nil, brand: String? = nil, symbol: String) {
        self.app = app
        self.brand = brand
        self.symbol = symbol
    }
}

/// A well-known place on macOS that tends to grow, with a pre-made classification.
/// The source of truth is `catalog/catalog.json` (see docs/catalog.md).
public struct KnownLocation: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// Paths with `~`; all are measured together (hard links deduplicated).
    public var paths: [String]
    public var category: FindingCategory
    public var safety: SafetyClass
    public var explanation: String
    public var action: CleanupAction
    public var command: String?
    public var needsAdmin: Bool
    public var icon: FindingIcon?
    public var confidence: String?
    public var source: String?
    /// 1–5: how common this is on developer Macs.
    public var popularity: Int?

    public init(id: String, title: String, paths: [String], category: FindingCategory, safety: SafetyClass,
                explanation: String, action: CleanupAction, command: String? = nil, needsAdmin: Bool = false,
                icon: FindingIcon? = nil) {
        self.id = id
        self.title = title
        self.paths = paths
        self.category = category
        self.safety = safety
        self.explanation = explanation
        self.action = action
        self.command = command
        self.needsAdmin = needsAdmin
        self.icon = icon
    }
}

public enum Catalog {
    /// All known locations, decoded once from the embedded catalog.
    public static let locations: [KnownLocation] = {
        do {
            return try JSONDecoder().decode([KnownLocation].self, from: Data(CatalogData.json.utf8))
        } catch {
            assertionFailure("catalog.json does not decode: \(error)")
            return []
        }
    }()

    public static func location(id: String) -> KnownLocation? {
        locations.first { $0.id == id }
    }
}
