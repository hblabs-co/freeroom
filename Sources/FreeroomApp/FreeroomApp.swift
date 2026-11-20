import AppKit
import FreeroomCore
import SwiftUI

@main
struct FreeroomApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(model)
                .id(model.language)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)

        // The only window. Settings and onboarding live inside it.
        Window("Freeroom", id: "main") {
            MainView()
                .environment(model)
                .id(model.language)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L("Settings…")) { model.openSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Menu bar glyph (+ optional free space). Also wires window opening for code paths outside
/// SwiftUI views (notifications, popover actions) and opens the window on first launch.
private struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuGlyph.image(usedFraction: model.usedFraction))
            if model.showFreeInMenuBar {
                Text(model.freeBytes.formattedBytes)
            }
        }
        .task {
            model.openWindowAction = { id in openWindow(id: id) }
            if !model.onboarded { model.openMainWindow() }
        }
    }
}
