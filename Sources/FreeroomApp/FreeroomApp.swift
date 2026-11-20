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
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)

        Window("Freeroom", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 780)

        Window("Welcome to Freeroom", id: "onboarding") {
            OnboardingView().environment(model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Menu bar glyph (+ free space). Also wires window opening for code paths outside SwiftUI views
/// (notifications, popover actions) and shows onboarding on first launch.
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
            if !model.onboarded {
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
