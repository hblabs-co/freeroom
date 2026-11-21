import AppKit
import FreeroomCore
import ServiceManagement
import SwiftUI

/// Removes everything Freeroom creates. Keep this list in sync with the cask's `zap` stanza
/// (scripts/release.sh).
enum Uninstaller {
    static let bundleId = "co.hblabs.freeroom"

    static var dataLocations: [String] {
        [
            "~/Library/Application Support/Freeroom",          // database: scans, findings, history
            "~/Library/Caches/Freeroom",                       // Claude Code launcher script
            "~/Library/Caches/\(bundleId)",
            "~/Library/HTTPStorages/\(bundleId)",
            "~/Library/HTTPStorages/\(bundleId).binarycookies",
            "~/Library/Saved Application State/\(bundleId).savedState",
            "~/Library/Preferences/\(bundleId).plist",
        ].map { PathUtils.expand($0) }
    }

    /// Installed with Homebrew? Then Homebrew must remove it, or its records get out of sync.
    static var installedWithHomebrew: Bool {
        ["/opt/homebrew/Caskroom/freeroom", "/usr/local/Caskroom/freeroom"].contains { FileManager.default.fileExists(atPath: $0) }
    }

    static let brewCommand = "brew uninstall --zap --cask freeroom"
    static let pluginCommand = "claude plugin uninstall freeroom@freeroom"

    /// One visible step of the uninstall. Each returns the paths it could not remove.
    enum Step: CaseIterable {
        case loginItem, data, settings, notifications, app

        var title: String {
            switch self {
            case .loginItem: L("Turning off open at login")
            case .data: L("Deleting scans, history and caches")
            case .settings: L("Removing settings")
            case .notifications: L("Clearing notifications")
            case .app: L("Moving the app to the Trash")
            }
        }

        var symbol: String {
            switch self {
            case .loginItem: "power"
            case .data: "cylinder.split.1x2"
            case .settings: "gearshape"
            case .notifications: "bell.slash"
            case .app: "trash"
            }
        }

        @MainActor
        func run() -> [String] {
            let fm = FileManager.default
            switch self {
            case .loginItem:
                try? SMAppService.mainApp.unregister()
                return []
            case .data:
                return dataLocations.filter { !$0.hasSuffix(".plist") }.compactMap { path in
                    guard fm.fileExists(atPath: path) else { return nil }
                    return (try? fm.removeItem(atPath: path)) == nil ? path : nil
                }
            case .settings:
                UserDefaults.standard.removePersistentDomain(forName: bundleId)
                UserDefaults.standard.synchronize()
                let plist = PathUtils.expand("~/Library/Preferences/\(bundleId).plist")
                try? fm.removeItem(atPath: plist)
                return []
            case .notifications:
                let center = UNUserNotificationCenter.current()
                center.removeAllDeliveredNotifications()
                center.removeAllPendingNotificationRequests()
                return []
            case .app:
                let url = Bundle.main.bundleURL
                return (try? fm.trashItem(at: url, resultingItemURL: nil)) == nil ? [url.path] : []
            }
        }
    }

    /// Quits without the normal termination path: a regular quit would write the window state and
    /// preferences straight back to disk, and a sheet that is still open can block `terminate`.
    @MainActor
    static func quitNow() {
        // Saved window state is written while the app runs; remove it one last time.
        try? FileManager.default.removeItem(atPath: PathUtils.expand("~/Library/Saved Application State/\(bundleId).savedState"))
        exit(0)
    }
}

import UserNotifications

/// Settings › About: "Uninstall Freeroom…" with an explicit list of what goes away.
struct UninstallSection: View {
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 8) {
            Button(role: .destructive) { confirming = true } label: {
                Label(L("Uninstall Freeroom…"), systemImage: "trash")
            }
            .controlSize(.regular)
        }
        .sheet(isPresented: $confirming) { UninstallSheet() }
    }
}

private struct UninstallSheet: View {
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case confirm, running, done }
    @State private var phase = Phase.confirm
    @State private var current = 0
    @State private var failed: [String] = []

    var body: some View {
        Group {
            switch phase {
            case .confirm: confirmView
            case .running, .done: progressView
            }
        }
        .padding(22)
        .frame(width: 560)
        .interactiveDismissDisabled(phase != .confirm)
        .animation(.smooth, value: phase)
        .animation(.smooth, value: current)
    }

    private var confirmView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Uninstall Freeroom"), systemImage: "trash").font(.fr(.title2).weight(.semibold))
            Text(L("This removes the app and everything it created on this Mac:")).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Uninstaller.dataLocations, id: \.self) { path in
                    Label(PathUtils.abbreviate(path), systemImage: "folder")
                        .font(.fr(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                }
                Label(L("Open at login, notifications, and the app itself"), systemImage: "app.badge")
                    .font(.fr(.caption))
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(L("The Claude Code plugin is part of Claude Code. Remove it there too:")).font(.fr(.callout))
                CopyField(text: Uninstaller.pluginCommand)
            }

            if Uninstaller.installedWithHomebrew {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L("Installed with Homebrew: uninstall it with Homebrew so nothing is left behind."),
                          systemImage: "info.circle")
                        .font(.fr(.callout))
                    CopyField(text: Uninstaller.brewCommand)
                }
            }

            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                if !Uninstaller.installedWithHomebrew {
                    Button(role: .destructive) { start() } label: { Text(L("Uninstall")) }
                        .buttonStyle(.borderedProminent).tint(Theme.danger)
                }
            }
        }
    }

    private var progressView: some View {
        let steps = Uninstaller.Step.allCases
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if phase == .done {
                    Image(systemName: failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.fr(.title)).foregroundStyle(failed.isEmpty ? Theme.accent : Theme.danger)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ProgressView().controlSize(.regular)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase == .done ? L("Freeroom was uninstalled") : L("Uninstalling Freeroom…"))
                        .font(.fr(.title2).weight(.semibold))
                    if phase == .done, failed.isEmpty {
                        Text(L("Closing in a moment…")).foregroundStyle(.secondary)
                    }
                }
            }

            ProgressView(value: Double(current), total: Double(steps.count)).tint(Theme.accent)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 10) {
                        Group {
                            if index < current {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            } else if index == current, phase == .running {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: step.symbol).foregroundStyle(.tertiary)
                            }
                        }
                        .frame(width: 20)
                        Text(step.title).foregroundStyle(index <= current ? .primary : .secondary)
                    }
                    .font(.fr(.body))
                }
            }

            if !failed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Some items could not be removed:")).font(.fr(.callout))
                    ForEach(failed, id: \.self) { path in
                        Text(PathUtils.abbreviate(path)).font(.fr(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
                HStack { Spacer(); Button(L("Quit")) { Uninstaller.quitNow() }.buttonStyle(.borderedProminent) }
            }
        }
    }

    private func start() {
        phase = .running
        Task { @MainActor in
            for (index, step) in Uninstaller.Step.allCases.enumerated() {
                current = index
                // Long enough to read each step; the work itself takes milliseconds.
                try? await Task.sleep(for: .milliseconds(450))
                failed += step.run()
            }
            current = Uninstaller.Step.allCases.count
            phase = .done
            guard failed.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1.8))
            Uninstaller.quitNow()
        }
    }
}
