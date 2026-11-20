import Foundation

/// A well-known place on macOS that tends to grow, with a pre-made classification.
public struct KnownLocation: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// Paths with `~`; all are measured together (hard links deduplicated).
    public var paths: [String]
    public var category: FindingCategory
    public var safety: SafetyClass
    public var explanation: String
    public var action: CleanupAction
    public var command: String?
    public var needsAdmin: Bool

    public init(id: String, title: String, paths: [String], category: FindingCategory, safety: SafetyClass,
                explanation: String, action: CleanupAction, command: String? = nil, needsAdmin: Bool = false) {
        self.id = id
        self.title = title
        self.paths = paths
        self.category = category
        self.safety = safety
        self.explanation = explanation
        self.action = action
        self.command = command
        self.needsAdmin = needsAdmin
    }
}

public enum Catalog {
    public static let locations: [KnownLocation] = [
        // MARK: Xcode / iOS
        .init(id: "xcode-derived-data", title: "Xcode DerivedData",
              paths: ["~/Library/Developer/Xcode/DerivedData"], category: .xcode, safety: .safe,
              explanation: "Build products and indexes for every project ever opened in Xcode. Rebuilt on the next build.",
              action: .delete),
        .init(id: "xcode-simulator-devices", title: "Simulator devices (apps and data)",
              paths: ["~/Library/Developer/CoreSimulator/Devices"], category: .xcode, safety: .safe,
              explanation: "Apps and data installed in iOS simulators. Erasing resets every simulator to factory state.",
              action: .command, command: "xcrun simctl erase all"),
        .init(id: "xcode-device-support", title: "iOS DeviceSupport",
              paths: ["~/Library/Developer/Xcode/iOS DeviceSupport", "~/Library/Developer/Xcode/watchOS DeviceSupport"],
              category: .xcode, safety: .safe,
              explanation: "Debug symbols copied from physical devices. Recreated when a device is connected again.",
              action: .delete),
        .init(id: "xcode-archives", title: "Xcode Archives",
              paths: ["~/Library/Developer/Xcode/Archives"], category: .xcode, safety: .review,
              explanation: "Archived app builds. Needed to symbolicate crash reports of released versions.",
              action: .trash),

        // MARK: App caches
        .init(id: "spotify-cache", title: "Spotify cache",
              paths: ["~/Library/Caches/com.spotify.client"], category: .appCaches, safety: .safe,
              explanation: "Cached songs. Spotify downloads them again when needed.", action: .delete),
        .init(id: "playwright-browsers", title: "Playwright browsers",
              paths: ["~/Library/Caches/ms-playwright"], category: .appCaches, safety: .safe,
              explanation: "Browsers downloaded for end-to-end tests. Reinstall with `npx playwright install`.",
              action: .delete),
        .init(id: "jetbrains-cache", title: "JetBrains caches",
              paths: ["~/Library/Caches/JetBrains"], category: .appCaches, safety: .safe,
              explanation: "IDE indexes. Rebuilt when a project is opened.", action: .delete),
        .init(id: "vscode-shipit", title: "VS Code update leftovers",
              paths: ["~/Library/Caches/com.microsoft.VSCode.ShipIt"], category: .appCaches, safety: .safe,
              explanation: "Installers of updates that were already applied.", action: .delete),
        .init(id: "browser-caches", title: "Browser caches",
              paths: ["~/Library/Caches/Google", "~/Library/Caches/company.thebrowser.Browser",
                      "~/Library/Caches/Firefox", "~/Library/Caches/com.microsoft.edgemac"],
              category: .appCaches, safety: .safe,
              explanation: "Web caches. Sessions, history and passwords are not stored here.", action: .delete),
        .init(id: "updater-caches", title: "App updater caches",
              paths: ["~/Library/Caches/electron", "~/Library/Caches/electron-builder",
                      "~/Library/Caches/lens-desktop-updater"],
              category: .appCaches, safety: .safe,
              explanation: "Downloaded installers and Electron runtimes for app updates.", action: .delete),

        // MARK: Developer caches
        .init(id: "npm-cache", title: "npm cache", paths: ["~/.npm/_cacache"], category: .devCaches, safety: .safe,
              explanation: "Downloaded npm packages. Fetched again on install.",
              action: .command, command: "npm cache clean --force"),
        .init(id: "pnpm-store", title: "pnpm store",
              paths: ["~/Library/pnpm/store", "~/Library/Caches/pnpm"], category: .devCaches, safety: .safe,
              explanation: "Content-addressable package store. Pruning removes packages no project references.",
              action: .command, command: "pnpm store prune"),
        .init(id: "yarn-cache", title: "Yarn cache", paths: ["~/Library/Caches/Yarn"], category: .devCaches,
              safety: .safe, explanation: "Downloaded Yarn packages.", action: .command, command: "yarn cache clean"),
        .init(id: "pip-cache", title: "pip cache", paths: ["~/Library/Caches/pip"], category: .devCaches,
              safety: .safe, explanation: "Downloaded Python wheels.", action: .command, command: "pip cache purge"),
        .init(id: "homebrew-cache", title: "Homebrew downloads", paths: ["~/Library/Caches/Homebrew"],
              category: .devCaches, safety: .safe,
              explanation: "Old bottles and downloads. Installed formulae are not affected.",
              action: .command, command: "brew cleanup --prune=all"),
        .init(id: "go-modcache", title: "Go module cache", paths: ["~/go/pkg/mod"], category: .devCaches,
              safety: .safe, explanation: "Downloaded Go modules. Fetched again by `go build`.",
              action: .command, command: "go clean -modcache"),
        .init(id: "go-build-cache", title: "Go build cache", paths: ["~/Library/Caches/go-build"],
              category: .devCaches, safety: .safe, explanation: "Compiled Go packages.",
              action: .command, command: "go clean -cache"),
        .init(id: "nuget-packages", title: "NuGet packages",
              paths: ["~/.nuget/packages", "~/.local/share/NuGet"], category: .devCaches, safety: .safe,
              explanation: "Downloaded .NET packages. Restored on the next build.",
              action: .command, command: "dotnet nuget locals all --clear"),
        .init(id: "gradle-cache", title: "Gradle caches", paths: ["~/.gradle/caches"], category: .devCaches,
              safety: .safe, explanation: "Downloaded dependencies and build cache.", action: .delete),
        .init(id: "maven-repo", title: "Maven repository", paths: ["~/.m2/repository"], category: .devCaches,
              safety: .safe, explanation: "Downloaded Java dependencies.", action: .delete),
        .init(id: "cargo-registry", title: "Cargo registry cache", paths: ["~/.cargo/registry"],
              category: .devCaches, safety: .safe, explanation: "Downloaded crates.", action: .delete),
        .init(id: "cocoapods-cache", title: "CocoaPods cache", paths: ["~/Library/Caches/CocoaPods"],
              category: .devCaches, safety: .safe, explanation: "Downloaded pods.", action: .delete),
        .init(id: "arduino-staging", title: "Arduino downloads", paths: ["~/Library/Arduino15/staging"],
              category: .devCaches, safety: .safe,
              explanation: "Installer archives of board packages that are already installed.", action: .delete),
        .init(id: "arduino-packages", title: "Arduino board packages", paths: ["~/Library/Arduino15/packages"],
              category: .devCaches, safety: .review,
              explanation: "Toolchains for Arduino/ESP32 boards. Safe to remove if you no longer use Arduino.",
              action: .trash),
        .init(id: "ollama-models", title: "Ollama models", paths: ["~/.ollama/models"], category: .devCaches,
              safety: .review, explanation: "Local AI models. Remove the ones you don't use with `ollama rm <model>`.",
              action: .none),
        .init(id: "whisper-models", title: "Whisper models", paths: ["~/.cache/whisper"], category: .devCaches,
              safety: .review, explanation: "Speech-to-text models. Downloaded again when used.", action: .trash),

        // MARK: Personal
        .init(id: "trash", title: "Trash", paths: ["~/.Trash"], category: .personal, safety: .review,
              explanation: "Files already moved to the Trash still use disk space until it is emptied.",
              action: .delete),
        .init(id: "downloads", title: "Downloads", paths: ["~/Downloads"], category: .personal, safety: .review,
              explanation: "Review by hand: installers and archives here are often no longer needed.",
              action: .none),

        // MARK: System
        .init(id: "system-temp", title: "System temporary files", paths: ["/private/var/folders"],
              category: .system, safety: .keep,
              explanation: "Managed by macOS and cleaned on restart. Do not delete by hand.", action: .none),
    ]

    public static func location(id: String) -> KnownLocation? {
        locations.first { $0.id == id }
    }
}
