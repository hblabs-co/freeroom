import FreeroomCore
import SwiftUI

/// 44 pt row: checkbox, icon, title + short meta, size bar, size, safety chip. No paragraphs.
struct FindingRow: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    let fraction: Double
    @State private var hovering = false

    private var selected: Bool { model.selection.contains(finding.id) }
    private var inspected: Bool { model.inspected == finding.id }
    private var fresh: Bool { model.freshIds.contains(finding.id) }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { selected },
                set: { on in if on { model.selection.insert(finding.id) } else { model.selection.remove(finding.id) } }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            .disabled(!finding.isCleanable)
            .help(finding.isCleanable ? L("Select") : L("Freeroom never deletes Keep items"))

            ItemIcon(icon: finding.icon, fallback: finding.categoryFallback, size: 30)

            HStack(spacing: 6) {
                Text(finding.displayTitle).font(.fr(.body).weight(.medium)).lineLimit(1)
                Text(finding.meta).foregroundStyle(.secondary).lineLimit(1)
                if finding.source == .agent { AgentMark(size: 11) }
                if finding.needsAdmin { Image(systemName: "lock.fill").font(.fr(.caption)).foregroundStyle(.secondary) }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            // The size bar is the first thing to go when the list column is narrow.
            ViewThatFits(in: .horizontal) {
                SizeBar(fraction: fraction, highlighted: selected).frame(width: 90)
                Color.clear.frame(width: 0)
            }
            Text(finding.reclaimable.formattedBytes)
                .font(.fr(.body).weight(.semibold)).monospacedDigit()
                .frame(width: 78, alignment: .trailing)
            SafetyBadge(safety: finding.safety).frame(width: 86, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .opacity(finding.safety == .keep ? 0.55 : 1)
        .background(
            Rectangle().fill(inspected ? Theme.accent.opacity(0.10)
                             : fresh ? Theme.agentSoft
                             : hovering ? Color.secondary.opacity(0.06) : .clear)
        )
        .overlay(alignment: .leading) {
            if fresh { Rectangle().fill(Theme.agent).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.inspected = finding.id }
        .onHover { hovering = $0 }
        .help(model.explanation(for: finding))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(finding.displayTitle), \(finding.reclaimable.formattedBytes), \(Theme.label(finding.safety)), \(String(format: L("found by %@"), finding.source == .agent ? "Claude Code" : L("rule")))")
        .accessibilityValue(selected ? L("selected") : L("not selected"))
        .accessibilityAction(named: Text(L("Inspect"))) { model.inspected = finding.id }
        .contextMenu {
            if let path = finding.paths.first { Button(L("Reveal in Finder")) { model.reveal(path) } }
            if finding.isCleanable { Button(L("Clean…")) { model.requestClean([finding]) } }
        }
        .animation(.smooth(duration: 1.6), value: fresh)
    }
}

/// Inspector: progressive disclosure. Icon, size, one sentence, what will happen, evidence, paths.
struct FindingInspector: View {
    @Environment(AppModel.self) private var model
    let finding: Finding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ItemIcon(icon: finding.icon, fallback: finding.categoryFallback, size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.displayTitle).font(.fr(.title3).weight(.semibold))
                    Text(finding.reclaimable.formattedBytes)
                        .font(.system(size: FontScale.size(30), weight: .semibold, design: .rounded)).monospacedDigit()
                    HStack { SafetyBadge(safety: finding.safety); SourceBadge(source: finding.source) }
                }
                TranslatedExplanation(finding: finding)

                actionCard

                if finding.sharedBytes > 0 {
                    InfoCard(symbol: "link", title: String(format: L("%@ won't be freed"), finding.sharedBytes.formattedBytes),
                             detail: L("Hard-linked from elsewhere (e.g. a package store)."))
                }

                if let v = finding.verification, !v.evidence.isEmpty {
                    DisclosureGroup(finding.safety == .safe ? L("Why it's safe") : L("Why to review")) {
                        HStack(alignment: .top, spacing: 8) {
                            if finding.source == .agent { AgentMark(size: 12) } else { Image(systemName: "ruler").foregroundStyle(.secondary) }
                            Text(v.evidence).font(.fr(.callout))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(finding.source == .agent ? AnyShapeStyle(Theme.agentSoft) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.top, 6)
                    }
                }

                if !finding.paths.isEmpty {
                    DisclosureGroup(String(format: L("Locations (%@)"), "\(finding.paths.count)")) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(finding.paths.prefix(30), id: \.self) { path in
                                Button { model.reveal(path) } label: {
                                    Label(PathUtils.abbreviate(path), systemImage: "folder")
                                        .font(.fr(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                }
                                .buttonStyle(.link)
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                if finding.isCleanable {
                    HStack {
                        Button(model.selection.contains(finding.id) ? L("Remove from selection") : L("Add to selection")) {
                            if model.selection.contains(finding.id) { model.selection.remove(finding.id) } else { model.selection.insert(finding.id) }
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                        Button(L("Clean now…")) { model.requestClean([finding]) }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var actionCard: some View {
        switch finding.action {
        case .command:
            InfoCard(symbol: "terminal", title: L("Runs the tool's own cleanup"),
                     detail: finding.needsAdmin ? L("Asks for your administrator password") : nil,
                     code: finding.command)
        case .delete:
            InfoCard(symbol: "xmark.bin", title: L("Deletes permanently"), detail: L("Regenerable: it comes back when needed."))
        case .trash:
            InfoCard(symbol: "trash", title: L("Moves to the Trash"), detail: L("Recoverable until you empty the Trash."))
        case .none:
            InfoCard(symbol: "info.circle", title: L("Nothing to run"), detail: L("Informational: review it yourself."))
        }
    }
}

struct InfoCard: View {
    let symbol: String
    let title: String
    var detail: String?
    var code: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.fr(.title3)).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.fr(.callout).weight(.semibold))
                if let detail { Text(detail).font(.fr(.caption)).foregroundStyle(.secondary) }
                if let code {
                    Text(code).font(.fr(.caption, design: .monospaced)).textSelection(.enabled)
                        .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// Disk map: one tile per reclaimable finding, area proportional to size, with its real icon.
struct TreemapView: View {
    @Environment(AppModel.self) private var model
    let findings: [Finding]

    /// Tiles below this share of the map are too small for an icon: they are grouped into one
    /// "+N more" tile instead of showing as empty boxes.
    private static let minShare = 0.018
    private static let maxTiles = 24

    var body: some View {
        let total = Double(findings.reduce(Int64(0)) { $0 + $1.reclaimable })
        let shown = Array(findings.prefix(Self.maxTiles).filter { total > 0 && Double($0.reclaimable) / total >= Self.minShare })
        let rest = findings.filter { f in !shown.contains { $0.id == f.id } }
        let restBytes = rest.reduce(Int64(0)) { $0 + $1.reclaimable }
        let weights = shown.map { Double($0.reclaimable) } + (rest.isEmpty ? [] : [Double(restBytes)])
        GeometryReader { geo in
            let rects = Treemap.layout(weights: weights, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, finding in
                    let rect = rects[index].insetBy(dx: 2, dy: 2)
                    if rect.width > 4 && rect.height > 4 {
                        TreemapTile(finding: finding, size: rect.size)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
                if !rest.isEmpty, let last = rects.last {
                    let rect = last.insetBy(dx: 2, dy: 2)
                    MoreTile(count: rest.count, bytes: restBytes, size: rect.size)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Disk map of reclaimable items"))
    }
}

struct TreemapTile: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    let size: CGSize
    @State private var hovering = false

    var body: some View {
        let selected = model.selection.contains(finding.id)
        let color = Theme.color(finding.safety)
        Button {
            if selected { model.selection.remove(finding.id) } else { model.selection.insert(finding.id) }
            model.inspected = finding.id
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(hovering ? 0.20 : 0.12))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : color.opacity(0.25), lineWidth: selected ? 2 : 0.5)
                VStack(alignment: .leading, spacing: 4) {
                    if min(size.width, size.height) >= 40 {
                        ItemIcon(icon: finding.icon, fallback: finding.categoryFallback,
                                 size: min(34, min(size.width, size.height) * 0.42))
                    }
                    Spacer(minLength: 0)
                    if size.width > 92 && size.height > 64 {
                        Text(finding.displayTitle).font(.fr(.caption).weight(.medium)).lineLimit(1)
                    }
                    if size.width > 60 && size.height > 50 {
                        Text(finding.reclaimable.formattedBytes).font(.fr(.caption).weight(.semibold)).monospacedDigit()
                    }
                }
                .padding(8)
                if size.width > 40 && size.height > 30 {
                    Image(systemName: selected ? "checkmark.circle.fill" : Theme.icon(finding.safety))
                        .foregroundStyle(selected ? Theme.accent : color)
                        .font(.fr(.caption))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(finding.displayTitle) · \(finding.reclaimable.formattedBytes)\n\(model.explanation(for: finding))")
        .accessibilityLabel("\(finding.displayTitle), \(finding.reclaimable.formattedBytes), \(Theme.label(finding.safety))")
    }
}

/// Explanation in the app language, with a one-click way to read the English original.
private struct TranslatedExplanation: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    @State private var showOriginal = false

    var body: some View {
        let translated = model.explanation(for: finding)
        let isTranslated = translated != finding.explanation
        VStack(alignment: .leading, spacing: 6) {
            Text(showOriginal ? finding.explanation : translated)
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if isTranslated {
                Button(showOriginal ? L("Show translation") : L("Show original (English)")) {
                    withAnimation(.snappy) { showOriginal.toggle() }
                }
                .buttonStyle(.link).font(.fr(.caption))
            }
        }
    }
}

/// Aggregates the many small items so the map never shows empty boxes.
private struct MoreTile: View {
    let count: Int
    let bytes: Int64
    let size: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.08))
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            VStack(spacing: 2) {
                if size.height > 34 {
                    Image(systemName: "square.grid.3x3.fill").foregroundStyle(.secondary)
                }
                Text("+\(count)").font(.fr(.callout).weight(.semibold))
                if size.width > 60 && size.height > 50 {
                    Text(bytes.formattedBytes).font(.fr(.caption)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .help(String(format: L("%@ smaller items · %@"), "\(count)", bytes.formattedBytes))
        .accessibilityLabel(String(format: L("%@ smaller items · %@"), "\(count)", bytes.formattedBytes))
    }
}
