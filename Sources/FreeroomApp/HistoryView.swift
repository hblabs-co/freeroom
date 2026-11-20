import FreeroomCore
import SwiftUI

/// What was cleaned, when, how, and how much it freed: grouped by day, newest first.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<String> = []

    private var days: [(Date, [HistoryEntry])] {
        let calendar = Calendar.current
        return Dictionary(grouping: model.history) { calendar.startOfDay(for: $0.at) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { $0.at > $1.at }) }
    }

    var body: some View {
        if model.history.isEmpty {
            ContentUnavailableView(L("Nothing cleaned yet"), systemImage: "clock.arrow.circlepath",
                                   description: Text(L("Everything Freeroom cleans will be listed here.")))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    summary
                    ForEach(days, id: \.0) { day, entries in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(day.formatted(date: .complete, time: .omitted)).font(.headline)
                                Spacer()
                                Text(entries.reduce(Int64(0)) { $0 + $1.freedBytes }.formattedBytes)
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                                    let key = "\(entry.findingId)-\(entry.at.timeIntervalSince1970)"
                                    HistoryRow(entry: entry, expanded: expanded.contains(key)) {
                                        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
                                    }
                                    if index < entries.count - 1 { Divider().padding(.leading, 58) }
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var summary: some View {
        let first = model.history.map(\.at).min()
        return HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Freed in total")).foregroundStyle(.secondary)
                Text(model.freedAllTime.formattedBytes)
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("\(model.history.count) \(L("cleanups"))", systemImage: "sparkles")
                if let first {
                    Label("\(L("Since")) \(first.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                }
            }
            .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    let entry: HistoryEntry
    let expanded: Bool
    let toggle: () -> Void

    private var how: (String, String) {
        switch entry.finding?.action {
        case .command: ("terminal", L("Cleanup command"))
        case .trash: ("trash", L("Moved to Trash"))
        case .delete: ("xmark.bin", L("Deleted"))
        default: ("checkmark.circle", L("Cleaned"))
        }
    }

    private var origin: String {
        switch entry.origin {
        case "notification": L("from a notification")
        case "menu": L("from the menu bar")
        case "cli": L("from the command line")
        default: L("in Freeroom")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ItemIcon(icon: entry.finding?.icon, fallback: entry.finding?.categoryFallback ?? "sparkles", size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.finding?.displayTitle ?? entry.title).font(.body.weight(.medium)).lineLimit(1)
                    HStack(spacing: 6) {
                        Label(how.1, systemImage: how.0)
                        Text("·")
                        Text(entry.at.formatted(date: .omitted, time: .shortened))
                        Text("·")
                        Text(origin)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.freedBytes.formattedBytes).font(.body.weight(.semibold)).monospacedDigit()
                if entry.finding != nil {
                    Button(action: toggle) { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help(L("Details"))
                }
            }
            if expanded, let finding = entry.finding {
                VStack(alignment: .leading, spacing: 6) {
                    if let command = finding.command, finding.action == .command {
                        Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .padding(6).background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    }
                    ForEach(finding.paths.prefix(20), id: \.self) { path in
                        HStack(spacing: 6) {
                            Image(systemName: "folder").foregroundStyle(.secondary)
                            Text(PathUtils.abbreviate(path)).font(.system(.caption, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        }
                    }
                    if finding.paths.count > 20 {
                        Text("+ \(finding.paths.count - 20)").font(.caption).foregroundStyle(.secondary)
                    }
                    if finding.action == .trash {
                        Button(L("Open Trash")) { model.openTrash() }.controlSize(.small)
                    }
                }
                .padding(.leading, 42)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { if entry.finding != nil { toggle() } }
    }
}
