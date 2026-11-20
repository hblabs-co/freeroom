import FreeroomCore
import SwiftUI

/// The popover under the menu bar glyph: one number, one action, three big wins.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandTitle(compact: true)
            if model.isScanning { ScanningStatus(compact: true) }
            header

            let safeTotal = model.safeFindings.reduce(Int64(0)) { $0 + $1.reclaimable }
            Button {
                model.requestClean(model.safeFindings)
            } label: {
                Label(safeTotal > 0 ? String(format: L("Free %@ safely"), safeTotal.formattedBytes) : L("Nothing safe to free right now"),
                      systemImage: "sparkles")
                    .font(.fr(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(safeTotal == 0)
            .keyboardShortcut(.defaultAction)

            if !model.suggestions.isEmpty {
                HStack {
                    Text(L("Biggest safe wins")).font(.fr(.caption).weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("See all")) { model.openMainWindow() }.buttonStyle(.link).font(.fr(.caption))
                }
                HStack(spacing: 8) {
                    ForEach(model.suggestions) { finding in
                        WinTile(finding: finding) { model.requestClean([finding]) }
                    }
                }
            } else if model.isRunningRules {
                HStack { ProgressView().controlSize(.small); Text(L("Measuring your disk…")).foregroundStyle(.secondary) }
            }

            agentCard

            if model.plugin.updateAvailable {
                PluginUpdateBanner(status: model.plugin)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 14) {
            DiskRing(used: model.usedFraction, warning: model.lowOnSpace)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(model.freeBytes.formattedBytes).font(.system(size: FontScale.size(26), weight: .semibold, design: .rounded)).monospacedDigit()
                }
                Text(String(format: L("free of %@"), model.totalBytes.formattedBytes)).foregroundStyle(.secondary)
                if model.lowOnSpace {
                    Label(String(format: L("Below your %@ threshold"), "\(model.lowDiskThresholdGB) GB"), systemImage: "exclamationmark.triangle.fill")
                        .font(.fr(.caption)).foregroundStyle(Theme.danger)
                }
            }
            Spacer()
            Button { model.openMainWindow() } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.borderless).help(L("Open Freeroom"))
        }
    }

    @ViewBuilder
    private var agentCard: some View {
        let agentFindings = model.findings.filter { $0.source == .agent }
        if model.lastAgentScan != nil {
            Button { model.openMainWindow() } label: {
                HStack(spacing: 10) {
                    AgentMark(size: 18)
                        .symbolEffect(.pulse, isActive: model.agentScanLive)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.agentScanLive ? L("Claude Code is scanning…") :
                                "Claude Code · \(model.lastAgentScan!.startedAt.formatted(.relative(presentation: .named)))")
                            .font(.fr(.callout).weight(.semibold))
                        Text(String(format: L("%@ findings"), "\(agentFindings.count)") + " · \(agentFindings.reduce(Int64(0)) { $0 + $1.reclaimable }.formattedBytes)")
                            .font(.fr(.caption))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.fr(.caption))
                }
                .foregroundStyle(Theme.agent)
                .padding(10)
                .background(Theme.agentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Button { model.launchClaudeScan() } label: {
                HStack(spacing: 10) {
                    RowIcon(symbol: "terminal")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Analyze with Claude Code")).font(.fr(.callout).weight(.semibold))
                        Text(L("Opens Terminal with /freeroom:scan")).font(.fr(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button { model.runRules() } label: {
                Image(systemName: "arrow.clockwise").symbolEffect(.rotate, isActive: model.isRunningRules)
            }.help(L("Check now (no AI)")).disabled(model.isRunningRules)
            Button { model.launchClaudeScan() } label: { Image(systemName: "terminal") }.help(L("Analyze with Claude Code"))
            Spacer()
            Toggle(isOn: Binding(get: { model.showFreeInMenuBar }, set: { model.showFreeInMenuBar = $0 })) {
                Image(systemName: "menubar.rectangle")
            }
            .toggleStyle(.button).help(L("Show free space in the menu bar"))
            if let scan = model.lastRuleScan {
                Text(String(format: L("Checked %@"), scan.startedAt.formatted(.relative(presentation: .named))))
                    .font(.fr(.caption)).foregroundStyle(.secondary)
            }
            Button { model.openSettings() } label: { Image(systemName: "gearshape") }.help(L("Settings"))
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help(L("Quit Freeroom"))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

/// Big icon tile for the top safe wins; tapping goes straight to the clean sheet.
struct WinTile: View {
    let finding: Finding
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ItemIcon(icon: finding.icon, fallback: finding.categoryFallback, size: 40)
                Text(finding.reclaimable.formattedBytes).font(.fr(.callout).weight(.semibold)).monospacedDigit()
                Text(finding.displayTitle).font(.fr(.caption2)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.vertical, 10).padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? AnyShapeStyle(Theme.accent.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.5))))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(String(format: L("%@: clean %@"), finding.displayTitle, finding.reclaimable.formattedBytes))
    }
}
