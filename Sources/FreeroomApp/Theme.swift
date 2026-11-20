import AppKit
import FreeroomCore
import SwiftUI

/// hblabs design tokens (design system v0.3): one blue accent, amber reserved for the agent.
enum Theme {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    // Brand blue scale (logo blue #1a4ddb = 600). The UI is monochrome blue: meaning comes from
    // icon and shape (filled ✓ vs outlined eye vs gray lock), never from hue alone.
    static let blue50 = dynamic(light: 0xF0F4FE, dark: 0x111A33)
    static let blue100 = dynamic(light: 0xE1E9FD, dark: 0x16224A)
    static let blue200 = dynamic(light: 0xC3D3FA, dark: 0x1D2F66)
    static let blue400 = dynamic(light: 0x4F78E8, dark: 0x8FB0FF)
    static let blue600 = dynamic(light: 0x1A4DDB, dark: 0x6594FA)
    static let blue800 = dynamic(light: 0x12338F, dark: 0xB9CDFF)

    /// Logo blue #1a4ddb, lighter in dark mode for AA contrast.
    static let accent = blue600
    /// Text/glyph drawn on a solid accent fill.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0A1430)
    /// Sacred: only the small agent glyph and its label. Never used as a background.
    static let agent = dynamic(light: 0xA86A0E, dark: 0xF0B54A)
    /// Neutral surface for agent cards (no yellow backgrounds).
    static let agentSoft = blue50
    static let safe = blue600
    static let review = blue400
    static let keep = dynamic(light: 0x5F5F66, dark: 0xA0A0A8)
    /// Only for warning icons and their one-line text; never as a background.
    static let danger = dynamic(light: 0xC2410C, dark: 0xFF9F6B)

    static func color(_ safety: SafetyClass) -> Color {
        switch safety {
        case .safe: safe
        case .review: review
        case .keep: keep
        }
    }

    /// Semantic colors always come with an icon (color is never the only signal).
    static func icon(_ safety: SafetyClass) -> String {
        switch safety {
        case .safe: "checkmark.circle.fill"
        case .review: "eye.circle"
        case .keep: "lock.circle.fill"
        }
    }

    static func label(_ safety: SafetyClass) -> String {
        switch safety {
        case .safe: L("Safe")
        case .review: L("Review")
        case .keep: L("Keep")
        }
    }

    static func categoryIcon(_ category: FindingCategory) -> String {
        switch category {
        case .docker: "shippingbox"
        case .xcode: "hammer"
        case .appCaches: "square.stack.3d.up"
        case .devCaches: "terminal"
        case .projects: "folder.badge.gearshape"
        case .personal: "person.crop.square"
        case .apps: "app.badge"
        case .system: "gearshape"
        case .other: "questionmark.folder"
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The agent marker: an amber hex-node glyph (hexagon outline with a center dot).
struct AgentMark: View {
    var size: CGFloat = 12
    var body: some View {
        ZStack {
            HexagonShape().stroke(Theme.agent, lineWidth: size * 0.14)
            Circle().fill(Theme.agent).frame(width: size * 0.28, height: size * 0.28)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(L("Agent"))
    }
}

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX, cy = rect.midY
        let r = min(w, h) / 2
        var path = Path()
        for i in 0..<6 {
            let angle = Double(i) * .pi / 3 - .pi / 2
            let point = CGPoint(x: cx + r * cos(angle) * 0.92, y: cy + r * sin(angle))
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

/// Menu bar glyph: the final Freeroom icon (HB hexagon + sweep + one glint), 18 pt artboard
/// from design/assets/freeroom-menubar-template.svg, rendered as a template image so macOS
/// tints it for light/dark menu bars. When the disk is low, a small dot marks it.
enum MenuGlyph {
    private static let hexagon = ##"<path d="M12 2.6 20.2 7.3v9.4L12 21.4 3.8 16.7V7.3Z" fill="none" stroke="#000" stroke-width="1.9" stroke-linejoin="round"/>"##
    private static let sweep = ##"<path d="M3.8 15.8C8 14.9 14 13.1 20.2 11.4v5.3L12 21.4 3.8 16.7Z" fill="#000"/>"##
    private static let glint = ##"<path d="M13.6 5.6Q14 8.1 16.4 8.6Q14 9.1 13.6 11.6Q13.2 9.1 10.8 8.6Q13.2 8.1 13.6 5.6Z" fill="#000"/>"##
    private static let lowDot = ##"<circle cx="20.5" cy="4" r="3" fill="#000"/>"##

    private static var cache: [Bool: NSImage] = [:]
    private static var scanCache: [Int: NSImage] = [:]

    /// Glint positions for the "scanning" animation (24×24 viewBox, inside the hexagon).
    private static let scanGlints: [(Double, Double)] = [(8.5, 7.8), (13.6, 8.6), (16.2, 11.2), (12.0, 12.4)]

    private static func glint(at x: Double, _ y: Double, r: Double = 2.6) -> String {
        "<path d=\"M\(x) \(y - r)Q\(x + 0.35) \(y - 0.35) \(x + r) \(y)Q\(x + 0.35) \(y + 0.35) \(x) \(y + r)Q\(x - 0.35) \(y + 0.35) \(x - r) \(y)Q\(x - 0.35) \(y - 0.35) \(x) \(y - r)Z\" fill=\"#000\"/>"
    }

    /// Frame `i` of the scanning animation: the glint moves while Freeroom or Claude Code scans.
    @MainActor
    static func scanningImage(frame i: Int) -> NSImage {
        let index = i % scanGlints.count
        if let cached = scanCache[index] { return cached }
        let (x, y) = scanGlints[index]
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24">"##
            + hexagon + sweep + glint(at: x, y) + "</svg>"
        let image = NSImage(data: Data(svg.utf8)) ?? image()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Freeroom – scanning"
        scanCache[index] = image
        return image
    }

    @MainActor
    static func image(low: Bool = false) -> NSImage {
        if let cached = cache[low] { return cached }
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24">"##
            + hexagon + sweep + (low ? lowDot : glint) + "</svg>"
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage(systemSymbolName: "hexagon", accessibilityDescription: "Freeroom")!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Freeroom"
        cache[low] = image
        return image
    }
}

struct SafetyBadge: View {
    let safety: SafetyClass
    var value: Int64? = nil
    var body: some View {
        // Safe = solid blue chip, Review = outlined blue chip, Keep = quiet gray chip.
        let label = Label(value.map { "\(Theme.label(safety)) \($0.formattedBytes)" } ?? Theme.label(safety),
                          systemImage: Theme.icon(safety))
            .monospacedDigit()
            .font(.fr(.caption).weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
        switch safety {
        case .safe:
            label.foregroundStyle(Theme.onAccent).background(Theme.accent, in: Capsule())
        case .review:
            label.foregroundStyle(Theme.blue800)
                .overlay(Capsule().strokeBorder(Theme.blue400, lineWidth: 1))
        case .keep:
            label.foregroundStyle(Theme.keep).background(Color.secondary.opacity(0.10), in: Capsule())
        }
    }
}

struct SourceBadge: View {
    let source: FindingSource
    var body: some View {
        switch source {
        case .agent:
            HStack(spacing: 4) { AgentMark(size: 10); Text(L("agent")) }
                .font(.fr(.caption2).weight(.semibold))
                .foregroundStyle(Theme.agent)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.agentSoft, in: Capsule())
        case .rule:
            Text(L("rule"))
                .font(.fr(.caption2).weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26, regular material before.
    @ViewBuilder
    func freeroomGlass(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
