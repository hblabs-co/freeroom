import FreeroomCore
import SwiftUI

/// Ring with the Freeroom glyph inside: how full the disk is at a glance.
struct DiskRing: View {
    let used: Double
    var size: CGFloat = 68
    var warning = false

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, used)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: used)
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: size * 0.48, height: size * 0.48)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if warning {
                // Warnings are signalled by a clear icon, not by recoloring surfaces.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: size * 0.26, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.danger)
                    .background(Circle().fill(.background).padding(-3))
                    .offset(x: 4, y: -4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(String(format: L("Disk %@ percent used"), "\(Int(used * 100))"))
    }
}

/// Segmented disk bar: Safe · Review · Keep · everything else · free.
struct DiskBar: View {
    let total: Int64
    let free: Int64
    let safe: Int64
    let review: Int64
    let keep: Int64
    /// Optional part of the free segment to highlight (what a clean will add).
    var incoming: Int64 = 0

    var body: some View {
        let other = max(0, total - free - safe - review - keep)
        let segments: [(Int64, AnyShapeStyle)] = [
            (safe, AnyShapeStyle(Theme.safe)),
            (review, AnyShapeStyle(Theme.review)),
            (keep, AnyShapeStyle(Theme.keep.opacity(0.6))),
            (other, AnyShapeStyle(Color.secondary.opacity(0.25))),
            (incoming, AnyShapeStyle(Theme.safe.opacity(0.35))),
            (max(0, free), AnyShapeStyle(Color.secondary.opacity(0.08))),
        ]
        // Widths are normalized to exactly the available width (minus the gaps), so the bar can
        // never grow wider than its column and draw under the inspector.
        let visible = segments.filter { $0.0 > 0 }
        let sum = Double(visible.reduce(Int64(0)) { $0 + $1.0 })
        let gap: CGFloat = 1.5
        GeometryReader { geo in
            let available = max(0, geo.size.width - gap * CGFloat(max(0, visible.count - 1)))
            HStack(spacing: gap) {
                ForEach(visible.indices, id: \.self) { i in
                    Rectangle().fill(visible[i].1)
                        .frame(width: sum > 0 ? available * CGFloat(Double(visible[i].0) / sum) : 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .clipShape(Capsule())
        }
        .clipped()
        .frame(height: 10)
        .animation(.smooth, value: free)
        .accessibilityElement()
        .accessibilityLabel(String(format: L("Disk: %@ safe, %@ to review, %@ free of %@"), safe.formattedBytes, review.formattedBytes, free.formattedBytes, total.formattedBytes))
    }
}

struct LegendDot: View {
    let symbol: String
    let color: Color
    let label: String
    let value: Int64
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(label).foregroundStyle(.secondary)
            Text(value.formattedBytes).monospacedDigit()
        }
        .font(.fr(.caption))
    }
}

/// Relative size bar used in rows.
struct SizeBar: View {
    let fraction: Double
    var highlighted = false
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(highlighted ? Theme.accent : Color.secondary.opacity(0.55))
                    .frame(width: max(3, geo.size.width * CGFloat(min(1, fraction))))
            }
        }
        .frame(height: 5)
    }
}

/// Small rounded icon tile for settings rows.
struct RowIcon: View {
    let symbol: String
    var tint: Color = .secondary
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: FontScale.size(12), weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
    }
}

/// "Freeroom by HB Labs SAS" with the app icon.
struct BrandTitle: View {
    var compact = false
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: compact ? 20 : 28, height: compact ? 20 : 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Freeroom").font(compact ? .headline : .title3.weight(.semibold))
                Text("by HB Labs SAS").font(.fr(.caption2)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Scanning…" status shown in the popover and the main window while a scan runs.
struct ScanningStatus: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            if model.agentScanLive {
                AgentMark(size: compact ? 14 : 18).symbolEffect(.pulse)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .symbolEffect(.rotate, isActive: true)
                    .foregroundStyle(Theme.accent)
            }
            Text(model.scanStatusText).font(compact ? .fr(.callout).weight(.semibold) : .fr(.body).weight(.semibold))
            Spacer()
            ProgressView().controlSize(.small)
        }
        .padding(compact ? 8 : 12)
        .background(Theme.blue50, in: RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.scanStatusText)
    }
}
