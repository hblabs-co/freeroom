import FreeroomCore
import SwiftUI

/// The popover under the menu bar glyph.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            DiskGauge(free: model.freeBytes, total: model.totalBytes)

            VStack(alignment: .leading, spacing: 8) {
                Text("Quick suggestions").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if model.suggestions.isEmpty {
                    Text(model.isRunningRules ? "Checking your disk…" : "Nothing big to clean right now.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(model.suggestions) { finding in
                    HStack(spacing: 10) {
                        Image(systemName: Theme.categoryIcon(finding.category))
                            .foregroundStyle(.secondary).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(finding.title).font(.callout).lineLimit(1)
                            Text(finding.sizeBytes.formattedBytes).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Clean") {
                            model.selection = [finding.id]
                            openMain()
                        }
                        .controlSize(.small)
                    }
                }
            }

            agentLine

            Divider()
            HStack {
                Button("Open Freeroom") { openMain() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                Button {
                    model.copyScanCommand()
                } label: {
                    Label("Copy /freeroom:scan", systemImage: "doc.on.doc")
                }
                .help("Paste it into Claude Code for a deep analysis")
                Spacer()
            }
            HStack {
                Button(model.isRunningRules ? "Checking…" : "Check now") { model.runRules() }
                    .disabled(model.isRunningRules)
                Spacer()
                Button("Settings…") { openSettings() }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
            Text("Freeroom").font(.headline)
            Spacer()
            if model.isRunningRules { ProgressView().controlSize(.small) }
        }
    }

    @ViewBuilder
    private var agentLine: some View {
        HStack(spacing: 6) {
            AgentMark(size: 11)
            if let scan = model.lastAgentScan {
                let count = model.findings.filter { $0.source == .agent }.count
                Text(model.agentScanLive
                     ? "Claude Code is scanning… \(count) findings so far"
                     : "Last agent scan \(scan.startedAt.formatted(.relative(presentation: .named))) · \(count) findings")
            } else {
                Text("No agent scan yet. Run /freeroom:scan in Claude Code.")
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.agent)
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct DiskGauge: View {
    let free: Int64
    let total: Int64

    var used: Double { total > 0 ? 1 - Double(free) / Double(total) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(free.formattedBytes).font(.title2.weight(.semibold)).monospacedDigit()
                Text("free of \(total.formattedBytes)").foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(used * 100))% used").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(used > 0.9 ? Theme.danger : Theme.accent)
                        .frame(width: geo.size.width * used)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }
}
