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
            HStack(spacing: 4) {
                Image(nsImage: MenuGlyph.image(usedFraction: model.usedFraction))
                if model.showFreeInMenuBar {
                    Text(model.freeBytes.formattedBytes)
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Freeroom", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
