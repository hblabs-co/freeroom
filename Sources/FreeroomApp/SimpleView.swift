import FreeroomCore
import SwiftUI

/// Simple mode: one number, one button, big icons. Details stay one click away (Detailed mode).
struct SimpleView: View {
    @Environment(AppModel.self) private var model

    private var safe: [Finding] { model.findings.filter { $0.safety == .safe && $0.isCleanable } }
    private var review: [Finding] { model.findings.filter { $0.safety == .review && $0.isCleanable } }

    var body: some View {
        if model.findings.isEmpty {
            EmptyStateView()
        } else {
            ScrollView {
                VStack(spacing: 26) {
                    if model.agentScanLive { AgentLiveBanner() }
                    hero
                    section(L("Safe to free"), symbol: Theme.icon(.safe), color: Theme.safe, items: safe)
                    section(L("Check these yourself"), symbol: Theme.icon(.review), color: Theme.review, items: review)
                }
                .padding(28)
                .padding(.bottom, 70)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var hero: some View {
        let safeTotal = safe.reduce(Int64(0)) { $0 + $1.reclaimable }
        return HStack(spacing: 28) {
            DiskRing(used: model.usedFraction, size: 120, warning: model.lowOnSpace)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("You can safely free")).font(.fr(.title3)).foregroundStyle(.secondary)
                Text(safeTotal.formattedBytes)
                    .font(.system(size: FontScale.size(56), weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(safeTotal)))
                Text(String(format: L("%@ free of %@"), model.freeBytes.formattedBytes, model.totalBytes.formattedBytes))
                    .foregroundStyle(.secondary).monospacedDigit()
                Button {
                    model.requestClean(model.safeFindings)
                } label: {
                    Label(L("Free it now"), systemImage: "sparkles").font(.fr(.title3).weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large)
                .disabled(safeTotal == 0)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func section(_ title: String, symbol: String, color: Color, items: [Finding]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(title, systemImage: symbol).font(.fr(.headline)).foregroundStyle(color)
                    Spacer()
                    Text(items.reduce(Int64(0)) { $0 + $1.reclaimable }.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)], spacing: 12) {
                    ForEach(items) { BigTile(finding: $0) }
                }
            }
        }
    }
}

/// Large selectable tile: icon, size, name. Click toggles selection; explanation on hover.
struct BigTile: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    @State private var hovering = false

    var body: some View {
        let selected = model.selection.contains(finding.id)
        Button {
            if selected { model.selection.remove(finding.id) } else { model.selection.insert(finding.id) }
        } label: {
            VStack(spacing: 8) {
                ItemIcon(icon: finding.icon, fallback: finding.categoryFallback, size: 52)
                Text(finding.reclaimable.formattedBytes).font(.fr(.title3).weight(.semibold)).monospacedDigit()
                Text(finding.displayTitle).font(.fr(.callout)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                    .frame(height: 36, alignment: .top)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? AnyShapeStyle(Theme.accent.opacity(0.12))
                      : hovering ? AnyShapeStyle(Color.secondary.opacity(0.08)) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 0.5))
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.fr(.title3)).foregroundStyle(selected ? Theme.accent : Color.secondary.opacity(0.5))
                    .padding(10)
            }
            .overlay(alignment: .topLeading) {
                if finding.source == .agent { AgentMark(size: 14).padding(12) }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(model.explanation(for: finding))
        .accessibilityLabel("\(finding.displayTitle), \(finding.reclaimable.formattedBytes)")
        .accessibilityValue(selected ? L("selected") : L("not selected"))
    }
}
