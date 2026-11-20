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
                .environment(\.locale, Locale(identifier: model.language))
                .font(.fr(.body))
                .id(model.appearanceKey)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)

        // The only window. Settings and onboarding live inside it.
        Window("Freeroom", id: "main") {
            MainView()
                .environment(model)
                .environment(\.locale, Locale(identifier: model.language))
                .font(.fr(.body))
                .id(model.appearanceKey)
                .modifier(MainWindowSizing(onboarded: model.onboarded, compact: model.simpleMode || model.route != .findings))
        }
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentSize)
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
            Image(nsImage: MenuGlyph.image(low: model.lowOnSpace))
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

/// Onboarding uses a compact, fixed-size window; afterwards the window can grow (min 980×640).
private struct MainWindowSizing: ViewModifier {
    let onboarded: Bool
    /// Simple mode, settings and history have no side columns, so the window can be narrower.
    let compact: Bool
    func body(content: Content) -> some View {
        if onboarded {
            content.frame(minWidth: compact ? 720 : 980, idealWidth: 1240, maxWidth: .infinity,
                          minHeight: 640, idealHeight: 800, maxHeight: .infinity)
        } else {
            content.frame(width: 620, height: 600)
        }
    }
}
