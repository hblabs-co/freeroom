import FreeroomCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Form {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                Toggle("Show free space in the menu bar", isOn: $model.showFreeInMenuBar)
                Picker("Explanations language", selection: $model.language) {
                    Text("English").tag("en")
                    Text("Español").tag("es")
                    Text("Deutsch").tag("de")
                }
                Text("Explanations are written in English. To read them in another language, run /freeroom:translate es in Claude Code (translations cost more tokens, so it is on demand).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Toggle("Send notifications", isOn: $model.notificationsEnabled)
                    .onChange(of: model.notificationsEnabled) { _, on in if on { model.requestNotificationPermission() } }
                Stepper("Warn below \(model.lowDiskThresholdGB) GB free", value: $model.lowDiskThresholdGB, in: 5...200, step: 5)
                Picker("Check the disk every", selection: $model.checkEveryHours) {
                    Text("2 hours").tag(2)
                    Text("6 hours").tag(6)
                    Text("12 hours").tag(12)
                    Text("24 hours").tag(24)
                }
                Text("Checks use the built-in rules only: no AI, no tokens. At most one notification per day.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("Notifications", systemImage: "bell") }

            Form {
                LabeledContent("Install") {
                    Text("/plugin install freeroom --marketplace hblabs-co/freeroom")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                LabeledContent("Scan") {
                    Text("/freeroom:scan").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                LabeledContent("CLI") {
                    Text(Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/freeroom").path)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                Text("The agent can measure and report, but it cannot delete. Only this app deletes, after you confirm.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("Claude Code", systemImage: "terminal") }

            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                Text("Freeroom \(Freeroom.version)").font(.headline)
                Text("Open source · MIT · by hblabs").foregroundStyle(.secondary)
                Link("github.com/hblabs-co/freeroom", destination: URL(string: "https://github.com/hblabs-co/freeroom")!)
                if let error = model.storeError {
                    Text(error).font(.caption).foregroundStyle(Theme.danger)
                }
            }
            .padding()
            .tabItem { Label("About", systemImage: "info.circle") }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 340)
    }
}
