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

    /// Unregisters the login item, deletes all data, moves the app to the Trash and quits.
    @MainActor
    static func uninstall() {
        try? SMAppService.mainApp.unregister()
        UserDefaults.standard.removePersistentDomain(forName: bundleId)
        let fm = FileManager.default
        for path in dataLocations where fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
        }
        // Delivered notifications belong to the app; clear them too.
        UNUserNotificationCenterClear.clear()
        try? fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        NSApp.terminate(nil)
    }
}

import UserNotifications
private enum UNUserNotificationCenterClear {
    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }
}

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

    var body: some View {
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
                    Button(role: .destructive) { Uninstaller.uninstall() } label: { Text(L("Uninstall")) }
                        .buttonStyle(.borderedProminent).tint(Theme.danger)
                }
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}
