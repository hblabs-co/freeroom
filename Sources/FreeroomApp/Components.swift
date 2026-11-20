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
                .stroke(warning ? Theme.danger : Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: used)
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: size * 0.48, height: size * 0.48)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Disk \(Int(used * 100)) percent used")
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
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(segments.indices, id: \.self) { i in
                    let (bytes, style) = segments[i]
                    if bytes > 0 && total > 0 {
                        Rectangle().fill(style)
                            .frame(width: max(2, geo.size.width * CGFloat(Double(bytes) / Double(total + incoming))))
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .animation(.smooth, value: free)
        .accessibilityElement()
        .accessibilityLabel("Disk: \(safe.formattedBytes) safe, \(review.formattedBytes) to review, \(free.formattedBytes) free of \(total.formattedBytes)")
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
        .font(.caption)
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
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
    }
}
