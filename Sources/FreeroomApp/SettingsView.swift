import FreeroomCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Form {
                row("power", "Open at login") { Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 })) }
                row("menubar.rectangle", "Free space in the menu bar") { Toggle("", isOn: $model.showFreeInMenuBar) }
                row("square.grid.3x3.square", "Show disk map") { Toggle("", isOn: $model.showDiskMap) }
                row("speaker.wave.2", "Sound when cleaning finishes") { Toggle("", isOn: $model.playSound) }
                row("clock.arrow.circlepath", "Check every", subtitle: "Rules only, no AI") {
                    Picker("", selection: $model.checkEveryHours) {
                        Text("2 h").tag(2); Text("6 h").tag(6); Text("12 h").tag(12); Text("24 h").tag(24)
                    }
                }
                row("globe", "Explanations", subtitle: "Translate with /freeroom:translate in Claude Code") {
                    Picker("", selection: $model.language) {
                        Text("English").tag("en"); Text("Español").tag("es"); Text("Deutsch").tag("de")
                    }
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                row("bell", "Notifications", subtitle: "At most one per day") {
                    Toggle("", isOn: $model.notificationsEnabled)
                        .onChange(of: model.notificationsEnabled) { _, on in if on { model.requestNotificationPermission() } }
                }
                row("exclamationmark.triangle", "Warn below") {
                    Stepper("\(model.lowDiskThresholdGB) GB", value: $model.lowDiskThresholdGB, in: 5...200, step: 5)
                }
            }
            .tabItem { Label("Alerts", systemImage: "bell") }

            Form {
                HStack(spacing: 12) {
                    AgentMark(size: 28)
                    VStack(alignment: .leading) {
                        Text("Claude Code plugin").font(.headline)
                        Text(model.lastAgentScan.map { "Last scan \($0.startedAt.formatted(.relative(presentation: .named)))" } ?? "No agent scan yet")
                            .foregroundStyle(.secondary)
                    }
                }
                row("arrow.down.circle", "Install") { CopyField(text: "/plugin install freeroom --marketplace hblabs-co/freeroom") }
                row("magnifyingglass", "Scan") { CopyField(text: "/freeroom:scan") }
                row("globe", "Translate") { CopyField(text: "/freeroom:translate es") }
                Label("The agent can measure and report. It cannot delete.", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("Claude Code", systemImage: "terminal") }

            Form {
                Section("Never touched") {
                    FlowChips(items: ["~/Documents", "~/Desktop", "~/Library", "~/.ssh", "Keychains", "Mail", "Messages", "iCloud Drive"],
                              symbol: "lock.fill")
                }
                Section("Allowed cleanup commands") {
                    FlowChips(items: Cleaner.allowedCommands.map { $0.prefix.prefix(3).joined(separator: " ") }, symbol: "terminal")
                }
                Label("Review items go to the Trash, so you can recover them.", systemImage: "trash")
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("Safety", systemImage: "checkmark.shield") }

            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
                Text("Freeroom \(Freeroom.version)").font(.title3.weight(.semibold))
                Text("Open source · MIT · by hblabs").foregroundStyle(.secondary)
                Link("github.com/hblabs-co/freeroom", destination: URL(string: "https://github.com/hblabs-co/freeroom")!)
                Text("brew install --cask hblabs-co/tap/freeroom").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("Brand logos from Simple Icons (CC0). Trademarks belong to their owners and are shown only to identify software on your Mac.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
                if let error = model.storeError { Text(error).font(.caption).foregroundStyle(Theme.danger) }
            }
            .padding()
            .tabItem { Label("About", systemImage: "info.circle") }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 380)
    }

    private func row<Content: View>(_ symbol: String, _ title: String, subtitle: String? = nil,
                                    @ViewBuilder content: () -> Content) -> some View {
        LabeledContent {
            content()
        } label: {
            HStack(spacing: 10) {
                RowIcon(symbol: symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

private struct CopyField: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(1)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
            .buttonStyle(.borderless).help("Copy")
        }
    }
}

private struct FlowChips: View {
    let items: [String]
    let symbol: String
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: symbol).font(.caption).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            }
        }
    }
}
