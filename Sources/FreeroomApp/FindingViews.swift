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
            .help(finding.isCleanable ? "Select" : "Freeroom never deletes Keep items")

            ItemIcon(icon: finding.icon, fallback: finding.categoryFallback, size: 30)

            HStack(spacing: 6) {
                Text(finding.title).font(.body.weight(.medium)).lineLimit(1)
                Text(finding.meta).foregroundStyle(.secondary).lineLimit(1)
                if finding.source == .agent { AgentMark(size: 11) }
                if finding.needsAdmin { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            SizeBar(fraction: fraction, highlighted: selected).frame(width: 90)
            Text(finding.reclaimable.formattedBytes)
                .font(.body.weight(.semibold)).monospacedDigit()
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
        .accessibilityLabel("\(finding.title), \(finding.reclaimable.formattedBytes), \(Theme.label(finding.safety)), found by \(finding.source == .agent ? "Claude Code" : "rule")")
        .accessibilityValue(selected ? "selected" : "not selected")
        .accessibilityAction(named: "Inspect") { model.inspected = finding.id }
        .contextMenu {
            if let path = finding.paths.first { Button("Reveal in Finder") { model.reveal(path) } }
            if finding.isCleanable { Button("Clean…") { model.requestClean([finding]) } }
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
                    Text(finding.title).font(.title3.weight(.semibold))
                    Text(finding.reclaimable.formattedBytes)
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    HStack { SafetyBadge(safety: finding.safety); SourceBadge(source: finding.source) }
                }
                Text(model.explanation(for: finding)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                actionCard

                if finding.sharedBytes > 0 {
                    InfoCard(symbol: "link", title: "\(finding.sharedBytes.formattedBytes) won't be freed",
                             detail: "Hard-linked from elsewhere (e.g. a package store).")
                }

                if let v = finding.verification, !v.evidence.isEmpty {
                    DisclosureGroup(finding.safety == .safe ? "Why it's safe" : "Why to review") {
                        HStack(alignment: .top, spacing: 8) {
                            if finding.source == .agent { AgentMark(size: 12) } else { Image(systemName: "ruler").foregroundStyle(.secondary) }
                            Text(v.evidence).font(.callout)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(finding.source == .agent ? AnyShapeStyle(Theme.agentSoft) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.top, 6)
                    }
                }

                if !finding.paths.isEmpty {
                    DisclosureGroup("Locations (\(finding.paths.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(finding.paths.prefix(30), id: \.self) { path in
                                Button { model.reveal(path) } label: {
                                    Label(PathUtils.abbreviate(path), systemImage: "folder")
                                        .font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                }
                                .buttonStyle(.link)
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                if finding.isCleanable {
                    HStack {
                        Button(model.selection.contains(finding.id) ? "Remove from selection" : "Add to selection") {
                            if model.selection.contains(finding.id) { model.selection.remove(finding.id) } else { model.selection.insert(finding.id) }
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                        Button("Clean now…") { model.requestClean([finding]) }
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
            InfoCard(symbol: "terminal", title: "Runs the tool's own cleanup",
                     detail: finding.needsAdmin ? "Asks for your administrator password" : nil,
                     code: finding.command)
        case .delete:
            InfoCard(symbol: "xmark.bin", title: "Deletes permanently", detail: "Regenerable: it comes back when needed.")
        case .trash:
            InfoCard(symbol: "trash", title: "Moves to the Trash", detail: "Recoverable until you empty the Trash.")
        case .none:
            InfoCard(symbol: "info.circle", title: "Nothing to run", detail: "Informational: review it yourself.")
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
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                if let code {
                    Text(code).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
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

    var body: some View {
        let items = Array(findings.prefix(40))
        GeometryReader { geo in
            let rects = Treemap.layout(weights: items.map { Double($0.reclaimable) },
                                       in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, finding in
                    let rect = rects[index].insetBy(dx: 2, dy: 2)
                    if rect.width > 4 && rect.height > 4 {
                        TreemapTile(finding: finding, size: rect.size)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Disk map of reclaimable items")
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
                        Text(finding.title).font(.caption.weight(.medium)).lineLimit(1)
                    }
                    if size.width > 60 && size.height > 50 {
                        Text(finding.reclaimable.formattedBytes).font(.caption.weight(.semibold)).monospacedDigit()
                    }
                }
                .padding(8)
                if size.width > 40 && size.height > 30 {
                    Image(systemName: selected ? "checkmark.circle.fill" : Theme.icon(finding.safety))
                        .foregroundStyle(selected ? Theme.accent : color)
                        .font(.caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(finding.title) · \(finding.reclaimable.formattedBytes)\n\(model.explanation(for: finding))")
        .accessibilityLabel("\(finding.title), \(finding.reclaimable.formattedBytes), \(Theme.label(finding.safety))")
    }
}
