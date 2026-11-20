import FreeroomCore
import SwiftUI

/// Three short steps: Full Disk Access → notifications → Claude Code (optional). Then the first scan.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var fullDiskAccess = false
    @State private var pluginState: Bool?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Capsule().fill(i <= step ? Theme.accent : Color.secondary.opacity(0.25)).frame(width: i == step ? 22 : 8, height: 6)
                }
            }
            .padding(.top, 22)
            .animation(.snappy, value: step)

            Group {
                switch step {
                case 0: diskAccess
                case 1: notifications
                default: claudeCode
                }
            }
            .transition(.push(from: .trailing))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Poll Full Disk Access while the user flips the switch in System Settings.
            while !Task.isCancelled {
                fullDiskAccess = model.hasFullDiskAccess
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func next() { withAnimation(.smooth) { step += 1 } }

    private func finish() {
        withAnimation(.smooth) { model.onboarded = true }
        model.runRules()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { model.expandMainWindow() }
    }

    private var diskAccess: some View {
        StepLayout(
            art: AnyView(HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Image(systemName: "externaldrive.fill.badge.checkmark").font(.system(size: FontScale.size(48))).foregroundStyle(Theme.accent)
            }),
            title: L("See your whole disk"),
            text: L("Full Disk Access lets Freeroom measure folders macOS protects, so sizes are exact. Nothing leaves your Mac."),
            status: fullDiskAccess ? AnyView(Label(L("Access granted"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.safe))
                                   : AnyView(HStack { ProgressView().controlSize(.small); Text(L("Waiting for System Settings…")).foregroundStyle(.secondary) }),
            primary: fullDiskAccess ? (L("Continue"), next) : (L("Open System Settings"), {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }),
            secondary: fullDiskAccess ? nil : (L("Later"), next)
        )
    }

    private var notifications: some View {
        StepLayout(
            art: AnyView(Image(systemName: "bell.badge.fill").font(.system(size: FontScale.size(56))).foregroundStyle(Theme.accent)
                .symbolRenderingMode(.hierarchical)),
            title: L("A heads-up, not a nag"),
            text: L("Freeroom checks your disk every few hours with its rules (no AI) and tells you when something big can go."),
            status: AnyView(HStack(spacing: 8) {
                Chip(symbol: "1.circle", text: L("1 per day max"))
                Chip(symbol: "moon", text: L("Quiet hours"))
                Chip(symbol: "cpu", text: L("No AI, no tokens"))
            }),
            primary: (L("Allow notifications"), { model.notificationsEnabled = true; model.requestNotificationPermission(); next() }),
            secondary: (L("Not now"), { model.notificationsEnabled = false; next() })
        )
    }

    private var claudeCode: some View {
        StepLayout(
            art: AnyView(HStack(spacing: 12) {
                VStack(spacing: 4) { AgentMark(size: 40); Text("Claude Code").font(.fr(.caption)).foregroundStyle(Theme.agent); Text(L("measures & reports")).font(.fr(.caption2)).foregroundStyle(.secondary) }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                VStack(spacing: 4) { Image(systemName: "cylinder.split.1x2").font(.system(size: FontScale.size(34))).foregroundStyle(.secondary); Text(L("Local store")).font(.fr(.caption)); Text(" ").font(.fr(.caption2)) }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                VStack(spacing: 4) { Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 42, height: 42); Text("Freeroom").font(.fr(.caption)); Text(L("you confirm, it cleans")).font(.fr(.caption2)).foregroundStyle(.secondary) }
            }),
            title: L("Optional: a deeper look with Claude Code"),
            text: L("The plugin lets your own Claude Code explain what rules can't (old archives, abandoned projects). It can measure and report, never delete."),
            status: AnyView(VStack(spacing: 8) {
                CopyField(text: "/plugin install freeroom --marketplace hblabs-co/freeroom", prominent: true)
                switch pluginState {
                case .some(true): Label(L("Plugin installed"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.safe)
                case .some(false): Label(L("Plugin not detected"), systemImage: "questionmark.circle").foregroundStyle(.secondary)
                case nil: ProgressView().controlSize(.small)
                }
                Button(L("Re-check")) { Task { pluginState = nil; pluginState = await model.pluginInstalled() } }.buttonStyle(.link)
            }.task { pluginState = await model.pluginInstalled() }),
            primary: (L("Start first scan"), finish),
            secondary: (L("Skip: rules only"), finish)
        )
    }
}

private struct StepLayout: View {
    let art: AnyView
    let title: String
    let text: String
    let status: AnyView
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            art.frame(height: 76).scaleEffect(0.85)
            Text(title).font(.fr(.title2).weight(.semibold)).multilineTextAlignment(.center)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            status.frame(minHeight: 30)
            Spacer()
            HStack {
                if let secondary { Button(secondary.0, action: secondary.1) }
                Spacer()
                Button(primary.0, action: primary.1).buttonStyle(.borderedProminent).tint(Theme.accent).keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 24)
        }
    }
}

struct Chip: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol).font(.fr(.caption))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: Capsule())
    }
}
