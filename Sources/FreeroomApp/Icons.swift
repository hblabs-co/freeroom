import AppKit
import FreeroomCore
import SwiftUI

/// Resolves a finding's icon: installed app icon → bundled brand logo (Simple Icons) → SF Symbol.
@MainActor
final class IconResolver {
    static let shared = IconResolver()

    enum Resolved {
        case app(NSImage)
        case brand(NSImage)
        case symbol(String)
    }

    private var cache: [String: Resolved] = [:]
    private let brandDirectory: URL?

    private init() {
        // Inside Freeroom.app: Contents/Resources/BrandIcons. During development: design/catalog-icons.
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("BrandIcons")
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("design/catalog-icons")
        brandDirectory = [bundled, dev].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
        NotificationCenter.default.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in IconResolver.shared.cache.removeAll() }
        }
    }

    func resolve(_ icon: FindingIcon?, fallback: String) -> Resolved {
        guard let icon else { return .symbol(fallback) }
        let key = "\(icon.app ?? "")|\(icon.brand ?? "")|\(icon.symbol)"
        if let cached = cache[key] { return cached }

        var result: Resolved = .symbol(icon.symbol.isEmpty ? fallback : icon.symbol)
        if let bundleId = icon.app,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            result = .app(NSWorkspace.shared.icon(forFile: url.path))
        } else if let slug = icon.brand, let dir = brandDirectory,
                  let image = NSImage(contentsOf: dir.appendingPathComponent("\(slug).svg")) {
            image.isTemplate = true // monochrome: tinted like text, never competes with the agent's amber
            result = .brand(image)
        }
        cache[key] = result
        return result
    }
}

/// A finding's icon in a continuous-corner tile (app icons are drawn bare: they bring their own shape).
struct ItemIcon: View {
    let icon: FindingIcon?
    var fallback: String = "folder"
    var size: CGFloat = 30

    var body: some View {
        let resolved = IconResolver.shared.resolve(icon, fallback: fallback)
        Group {
            switch resolved {
            case .app(let image):
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: size * 1.12, height: size * 1.12)
            case .brand(let image):
                Image(nsImage: image).resizable().renderingMode(.template).scaledToFit()
                    .foregroundStyle(.primary)
                    .padding(size * 0.22)
                    .frame(width: size, height: size)
                    .background(tile)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(tile)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

extension Finding {
    var categoryFallback: String { Theme.categoryIcon(category) }
}
