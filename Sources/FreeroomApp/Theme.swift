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

    /// Logo blue #1a4ddb, lighter in dark mode for AA contrast.
    static let accent = dynamic(light: 0x1A4DDB, dark: 0x6594FA)
    /// Sacred: only for things the AI agent did or said.
    static let agent = dynamic(light: 0xA86A0E, dark: 0xF0B54A)
    static let agentSoft = dynamic(light: 0xFDF0DC, dark: 0x3A2C14)
    static let safe = dynamic(light: 0x1F7A47, dark: 0x5FD394)
    static let review = dynamic(light: 0x0E6F84, dark: 0x5CC8DE)
    static let keep = dynamic(light: 0x5F5F66, dark: 0xA0A0A8)
    static let danger = dynamic(light: 0xB42318, dark: 0xFF8A80)

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
        case .review: "eye.circle.fill"
        case .keep: "lock.circle.fill"
        }
    }

    static func label(_ safety: SafetyClass) -> String {
        switch safety {
        case .safe: "Safe"
        case .review: "Review"
        case .keep: "Keep"
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
        .accessibilityLabel("Agent")
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

/// Menu bar glyph: the Freeroom hexagon filled from the bottom by how full the disk is.
enum MenuGlyph {
    @MainActor
    static func image(usedFraction: Double) -> NSImage {
        let size = CGSize(width: 18, height: 18)
        let view = ZStack {
            HexagonShape().stroke(Color.black, lineWidth: 1.6)
            HexagonShape()
                .fill(Color.black)
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: size.height * max(0.12, min(1, usedFraction)))
                }
                .padding(2.2)
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "hexagon", accessibilityDescription: nil)!
        image.isTemplate = true
        image.size = size
        return image
    }
}

struct SafetyBadge: View {
    let safety: SafetyClass
    var value: Int64? = nil
    var body: some View {
        Label(value.map { "\(Theme.label(safety)) \($0.formattedBytes)" } ?? Theme.label(safety), systemImage: Theme.icon(safety))
            .monospacedDigit()
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.color(safety))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Theme.color(safety).opacity(0.12), in: Capsule())
    }
}

struct SourceBadge: View {
    let source: FindingSource
    var body: some View {
        switch source {
        case .agent:
            HStack(spacing: 4) { AgentMark(size: 10); Text("agent") }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.agent)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.agentSoft, in: Capsule())
        case .rule:
            Text("rule")
                .font(.caption2.weight(.semibold))
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
