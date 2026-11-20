import FreeroomCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: SafetyClass? = nil
    @State private var sourceFilter: FindingSource? = nil
    @State private var search = ""
    @State private var expanded: Set<String> = []
    @State private var confirming = false

    private var visible: [Finding] {
        model.findings.filter { f in
            (filter == nil || f.safety == filter)
                && (sourceFilter == nil || f.source == sourceFilter)
                && (search.isEmpty || f.title.localizedCaseInsensitiveContains(search)
                    || f.paths.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    private var grouped: [(FindingCategory, [Finding])] {
        let groups = Dictionary(grouping: visible, by: \.category)
        return FindingCategory.allCases.compactMap { c in groups[c].map { (c, $0) } }
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            summary
            Divider()
            if model.findings.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(grouped, id: \.0) { category, items in
                        Section {
                            ForEach(items) { finding in
                                FindingRow(finding: finding, expanded: expanded.contains(finding.id)) {
                                    if expanded.contains(finding.id) { expanded.remove(finding.id) } else { expanded.insert(finding.id) }
                                }
                            }
                        } header: {
                            Label(category.title, systemImage: Theme.categoryIcon(category))
                        }
                    }
                }
                .listStyle(.inset)
            }
            selectionBar
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search findings")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Source", selection: $sourceFilter) {
                    Text("All sources").tag(FindingSource?.none)
                    Text("Rules").tag(FindingSource?.some(.rule))
                    Text("Agent").tag(FindingSource?.some(.agent))
                }
                .pickerStyle(.menu)
            }
            ToolbarItem {
                Button { model.runRules() } label: {
                    Label("Check now", systemImage: model.isRunningRules ? "hourglass" : "arrow.clockwise")
                }
                .disabled(model.isRunningRules)
                .help("Run the rule engine (no AI)")
            }
        }
        .sheet(isPresented: $confirming) {
            ConfirmSheet().environment(model)
        }
        .navigationTitle("Freeroom")
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 24) {
            DiskGauge(free: model.freeBytes, total: model.totalBytes).frame(maxWidth: 320)
            ForEach(SafetyClass.allCases, id: \.self) { safety in
                Button {
                    filter = filter == safety ? nil : safety
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(Theme.label(safety), systemImage: Theme.icon(safety))
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.color(safety))
                        Text(model.total(safety).formattedBytes).font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    .padding(10)
                    .frame(minWidth: 110, alignment: .leading)
                    .background(filter == safety ? Theme.color(safety).opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if model.agentScanLive {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    AgentMark(size: 12)
                    Text("Live from Claude Code").font(.callout).foregroundStyle(Theme.agent)
                }
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if model.isRunningRules {
                ProgressView("Measuring your disk…")
            } else {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Theme.accent)
                Text("No findings yet").font(.title3.weight(.semibold))
                Text("Run the built-in check, or ask Claude Code for a deep analysis with /freeroom:scan.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Check now") { model.runRules() }.buttonStyle(.borderedProminent).tint(Theme.accent)
                    Button("Copy /freeroom:scan") { model.copyScanCommand() }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var selectionBar: some View {
        HStack {
            if model.selection.isEmpty {
                Text("Select findings to clean. Nothing is deleted until you confirm.").foregroundStyle(.secondary)
            } else {
                Text("\(model.selection.count) selected · \(model.selectedBytes.formattedBytes)")
                    .monospacedDigit().font(.callout.weight(.semibold))
                Text("→ about \((model.freeBytes + model.selectedBytes).formattedBytes) free")
                    .foregroundStyle(.secondary).monospacedDigit()
                Button("Clear") { model.selection = [] }.buttonStyle(.borderless)
            }
            Spacer()
            Button("Review & clean…") { confirming = true }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(model.selection.isEmpty || model.cleaning)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .freeroomGlass(cornerRadius: 0)
    }
}

struct FindingRow: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { model.selection.contains(finding.id) },
                    set: { on in if on { model.selection.insert(finding.id) } else { model.selection.remove(finding.id) } }
                ))
                .labelsHidden()
                .disabled(finding.safety == .keep || finding.action == .none)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(finding.title).font(.body.weight(.medium))
                        SourceBadge(source: finding.source)
                        if finding.verification?.measuredByFreeroom == true {
                            Image(systemName: "checkmark.seal").foregroundStyle(Theme.accent).help("Measured by Freeroom")
                        }
                        if finding.needsAdmin {
                            Image(systemName: "lock.shield").foregroundStyle(.secondary).help("Needs administrator rights")
                        }
                    }
                    Text(model.explanation(for: finding))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(expanded ? nil : 1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(finding.sizeBytes.formattedBytes).font(.body.weight(.semibold)).monospacedDigit()
                    SafetyBadge(safety: finding.safety)
                }
                Button(action: toggle) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }
            if expanded { details.padding(.leading, 34) }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let command = finding.command {
                LabeledContent("Command") {
                    Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
            LabeledContent("Action") { Text(actionText) }
            if finding.sharedBytes > 0 {
                LabeledContent("Shared") {
                    Text("\(finding.sharedBytes.formattedBytes) is hard-linked elsewhere and will not be freed")
                }
            }
            if let v = finding.verification, !v.evidence.isEmpty {
                LabeledContent("Evidence") { Text(v.evidence) }
            }
            ForEach(finding.paths.prefix(8), id: \.self) { path in
                Button(PathUtils.abbreviate(path)) { model.reveal(path) }
                    .buttonStyle(.link).font(.system(.caption, design: .monospaced))
            }
            if finding.paths.count > 8 {
                Text("+ \(finding.paths.count - 8) more paths").font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var actionText: String {
        switch finding.action {
        case .command: "Run the tool's own cleanup command"
        case .trash: "Move to Trash (recoverable)"
        case .delete: "Delete permanently (regenerable)"
        case .none: "Informational: nothing to run"
        }
    }
}
