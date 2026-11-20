import FreeroomCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Form {
                row("power", L("Open at login")) { Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 })) }
                row("menubar.rectangle", L("Free space in the menu bar")) { Toggle("", isOn: $model.showFreeInMenuBar) }
                row("square.grid.3x3.square", L("Show disk map")) { Toggle("", isOn: $model.showDiskMap) }
row("textformat.size", L("Text size")) {
                    Picker("", selection: $model.textSize) {
                        Text(L("Small")).tag(FontScale.Size.small)
                        Text(L("Medium")).tag(FontScale.Size.medium)
                        Text(L("Large")).tag(FontScale.Size.large)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                                row("rectangle.split.3x1", L("Simple mode"), subtitle: L("Big icons and one button; switch anytime in the toolbar")) { Toggle("", isOn: Binding(get: { model.simpleMode }, set: { model.switchMode(simple: $0) })) }
                row("speaker.wave.2", L("Sound when cleaning finishes")) { Toggle("", isOn: $model.playSound) }
                row("clock.arrow.circlepath", L("Check every"), subtitle: L("Rules only, no AI")) {
                    Picker("", selection: $model.checkEveryHours) {
                        Text(String(format: L("%@ h"), "2")).tag(2); Text(String(format: L("%@ h"), "6")).tag(6); Text(String(format: L("%@ h"), "12")).tag(12); Text(String(format: L("%@ h"), "24")).tag(24)
                    }
                }
                row("globe", L("Language"), subtitle: String(format: L("Agent explanations: %@"), "/freeroom:translate \(model.language)")) {
                    Picker("", selection: $model.language) {
                        ForEach(L10n.languages) { Text($0.name).tag($0.id) }
                    }
                }
            }
            .tabItem { Label(L("General"), systemImage: "gearshape") }

            Form {
                row("bell", L("Notifications"), subtitle: L("At most one per day")) {
                    Toggle("", isOn: $model.notificationsEnabled)
                        .onChange(of: model.notificationsEnabled) { _, on in if on { model.requestNotificationPermission() } }
                }
                row("exclamationmark.triangle", L("Warn below")) {
                    Stepper("\(model.lowDiskThresholdGB) GB", value: $model.lowDiskThresholdGB, in: 5...200, step: 5)
                }
            }
            .tabItem { Label(L("Alerts"), systemImage: "bell") }

            Form {
                HStack(spacing: 12) {
                    AgentMark(size: 28)
                    VStack(alignment: .leading) {
                        Text(L("Claude Code plugin")).font(.fr(.headline))
                        Text(model.lastAgentScan.map { String(format: L("Last scan %@"), $0.startedAt.formatted(.relative(presentation: .named))) } ?? L("No agent scan yet"))
                            .foregroundStyle(.secondary)
                    }
                }
                PluginVersionCard()
                row("arrow.triangle.2.circlepath", L("Check for plugin updates"), subtitle: L("Asks GitHub once a day. Nothing about you is sent.")) {
                    Toggle("", isOn: $model.checkPluginUpdates)
                }
                row("arrow.down.circle", L("Install")) { CopyField(text: "/plugin install freeroom --marketplace hblabs-co/freeroom") }
                row("magnifyingglass", L("Scan")) { CopyField(text: "/freeroom:scan") }
                row("globe", L("Translate")) { CopyField(text: "/freeroom:translate es") }
                Label(L("The agent can measure and report. It cannot delete."), systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("Claude Code", systemImage: "terminal") }

            Form {
                Section(L("Never touched")) {
                    FlowChips(items: ["~/Documents", "~/Desktop", "~/Library", "~/.ssh", L("Keychains"), L("Mail"), L("Messages"), "iCloud Drive"],
                              symbol: "lock.fill")
                }
                Section(L("Allowed cleanup commands")) {
                    FlowChips(items: Cleaner.allowedCommands.map { $0.prefix.prefix(3).joined(separator: " ") }, symbol: "terminal")
                }
                Label(L("Review items go to the Trash, so you can recover them."), systemImage: "trash")
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label(L("Safety"), systemImage: "checkmark.shield") }

            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
                Text("Freeroom \(Freeroom.version)").font(.fr(.title3).weight(.semibold))
                Text("by HB Labs SAS").font(.fr(.headline)).foregroundStyle(.secondary)
                Text(L("Open source") + " · MIT").foregroundStyle(.secondary)
                Link("github.com/hblabs-co/freeroom", destination: URL(string: "https://github.com/hblabs-co/freeroom")!)
                Text("brew install --cask hblabs-co/tap/freeroom").font(.fr(.caption, design: .monospaced)).textSelection(.enabled)
                Text(L("Brand logos from Simple Icons (CC0). Trademarks belong to their owners and are shown only to identify software on your Mac."))
                    .font(.fr(.caption2)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
                if let error = model.storeError { Text(error).font(.fr(.caption)).foregroundStyle(Theme.danger) }
            }
            .padding()
            .tabItem { Label(L("About"), systemImage: "info.circle") }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
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
                    if let subtitle { Text(subtitle).font(.fr(.caption)).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

/// A command with a Copy button that confirms with a checkmark.
struct CopyField: View {
    let text: String
    var prominent = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(text).font(.system(prominent ? .callout : .caption, design: .monospaced))
                .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                withAnimation(.snappy) { copied = true }
                Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation { copied = false } }
            } label: {
                Label(copied ? L("Copied") : L("Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .controlSize(prominent ? .regular : .small)
            .tint(copied ? Theme.safe : nil)
        }
        .padding(prominent ? 8 : 0)
        .background(prominent ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FlowChips: View {
    let items: [String]
    let symbol: String
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: symbol).font(.fr(.caption)).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            }
        }
    }
}
