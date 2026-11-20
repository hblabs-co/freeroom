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

    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Label(L("Cleanups"), systemImage: "sparkles").tag(0)
                Label(L("Scans"), systemImage: "magnifyingglass").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .padding(.top, 14)
            if tab == 0 { cleanups } else { RunsView() }
        }
    }

    @ViewBuilder
    private var cleanups: some View {
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
                                Text(day.formatted(date: .complete, time: .omitted)).font(.fr(.headline))
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
                    .font(.system(size: FontScale.size(40), weight: .semibold, design: .rounded)).monospacedDigit()
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
                    Text(entry.finding?.displayTitle ?? entry.title).font(.fr(.body).weight(.medium)).lineLimit(1)
                    HStack(spacing: 6) {
                        Label(how.1, systemImage: how.0)
                        Text("·")
                        Text(entry.at.formatted(date: .omitted, time: .shortened))
                        Text("·")
                        Text(origin)
                    }
                    .font(.fr(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.freedBytes.formattedBytes).font(.fr(.body).weight(.semibold)).monospacedDigit()
                if entry.finding != nil {
                    Button(action: toggle) { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help(L("Details"))
                }
            }
            if expanded, let finding = entry.finding {
                VStack(alignment: .leading, spacing: 6) {
                    if let command = finding.command, finding.action == .command {
                        Text(command).font(.fr(.caption, design: .monospaced)).textSelection(.enabled)
                            .padding(6).background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    }
                    ForEach(finding.paths.prefix(20), id: \.self) { path in
                        HStack(spacing: 6) {
                            Image(systemName: "folder").foregroundStyle(.secondary)
                            Text(PathUtils.abbreviate(path)).font(.fr(.caption, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        }
                    }
                    if finding.paths.count > 20 {
                        Text("+ \(finding.paths.count - 20)").font(.fr(.caption)).foregroundStyle(.secondary)
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

/// Every run, rule check or Claude Code scan, with what it found. Expand to see the findings.
struct RunsView: View {
    @Environment(AppModel.self) private var model
    @State private var runs: [ScanSummary] = []
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: L("%@ runs"), "\(runs.count)")).font(.fr(.title3).weight(.semibold))
                        Button { model.revealDatabase() } label: {
                            Label(PathUtils.abbreviate(model.databasePath), systemImage: "cylinder.split.1x2")
                                .font(.fr(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        }
                        .buttonStyle(.link)
                        .help(L("Everything is stored locally in this file. Click to show it in Finder."))
                    }
                    Spacer()
                    Button { model.launchClaudeScan() } label: {
                        Label { Text(L("Analyze with Claude Code")) } icon: { AgentMark(size: 13) }
                    }
                    .buttonStyle(.bordered)
                    Button { model.runRules() } label: { Label(L("Check now"), systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered).disabled(model.isRunningRules)
                }
                VStack(spacing: 0) {
                    ForEach(runs) { run in
                        RunRow(run: run, expanded: expanded.contains(run.id)) {
                            withAnimation(.snappy) {
                                if expanded.contains(run.id) { expanded.remove(run.id) } else { expanded.insert(run.id) }
                            }
                        }
                        if run.id != runs.last?.id { Divider().padding(.leading, 52) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .task(id: model.lastRuleScan?.id ?? "" + (model.lastAgentScan?.id ?? "")) { runs = model.scanSummaries() }
        .onAppear { runs = model.scanSummaries() }
    }
}

private struct RunRow: View {
    @Environment(AppModel.self) private var model
    let run: ScanSummary
    let expanded: Bool
    let toggle: () -> Void
    @State private var items: [Finding] = []

    private var isAgent: Bool { run.scan.source == .agent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Group {
                    if isAgent { AgentMark(size: 22) } else { RowIcon(symbol: "ruler") }
                }
                .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isAgent ? L("Claude Code scan") : L("Rule check")).font(.fr(.body).weight(.medium))
                        if let v = run.scan.pluginVersion {
                            Text("v\(v)").font(.fr(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).background(.quaternary.opacity(0.6), in: Capsule())
                        }
                        if run.scan.endedAt == nil {
                            Label(L("running"), systemImage: "circle.dotted").font(.fr(.caption)).foregroundStyle(Theme.accent)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(run.scan.startedAt.formatted(date: .abbreviated, time: .shortened))
                        if let d = run.duration {
                            Text("·")
                            Text(Duration.seconds(d).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
                        }
                        if let note = run.scan.note, !note.isEmpty, note != "auto" { Text("·"); Text(note).lineLimit(1) }
                    }
                    .font(.fr(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(run.totalBytes.formattedBytes).font(.fr(.body).weight(.semibold)).monospacedDigit()
                    Text(String(format: L("%@ findings"), "\(run.findingCount)")).font(.fr(.caption)).foregroundStyle(.secondary)
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items.prefix(40)) { f in
                        HStack(spacing: 10) {
                            ItemIcon(icon: f.icon, fallback: f.categoryFallback, size: 22)
                            Text(f.displayTitle).lineLimit(1)
                            Spacer()
                            Text(f.sizeBytes.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                            SafetyBadge(safety: f.safety).frame(width: 86, alignment: .leading)
                        }
                    }
                    if items.count > 40 { Text("+ \(items.count - 40)").font(.fr(.caption)).foregroundStyle(.secondary) }
                    HStack {
                        Spacer()
                        Button { model.exportScan(run) } label: { Label(L("Export report…"), systemImage: "square.and.arrow.up") }
                            .controlSize(.small)
                    }
                }
                .padding(.leading, 40)
                .task { items = model.findings(forScan: run.id) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}
