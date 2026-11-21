import AppKit
import FreeroomCore

/// Demo mode for screenshots: `FREEROOM_DEMO=1`. Sample findings in a throwaway database, a fixed
/// disk size, no real scans or notifications, and its own preferences domain so the user's settings
/// are never touched. Nothing here runs unless the variable is set. See scripts/screenshots.sh.
enum Demo {
    static let isOn = ProcessInfo.processInfo.environment["FREEROOM_DEMO"] == "1"

    static let totalBytes: Int64 = 494_380_000_000
    static let freeBytes: Int64 = 31_200_000_000
    static let defaultsSuite = "co.hblabs.freeroom.demo"

    static var databasePath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("freeroom-demo.db")
    }

    private static let gb: Int64 = 1_000_000_000
    private static let mb: Int64 = 1_000_000

    /// Catalog entries shown as rule findings, with sample sizes.
    private static let catalogSizes: [(String, Int64)] = [
        ("xcode-derived-data", 48_600 * mb),
        ("xcode-simulator-devices", 31_200 * mb),
        ("xcode-device-support", 14_800 * mb),
        ("ollama-models", 12_400 * mb),
        ("ios-backups", 22_900 * mb),
        ("pnpm-store", 7_300 * mb),
        ("homebrew-cache", 4_100 * mb),
        ("npm-cache", 3_600 * mb),
        ("xcode-archives", 6_200 * mb),
        ("android-sdk", 9_800 * mb),
        ("go-build-cache", 2_900 * mb),
        ("cargo-registry", 2_200 * mb),
        ("yarn-cache", 1_900 * mb),
        ("cocoapods-cache", 1_400 * mb),
        ("pip-cache", 1_100 * mb),
        ("spotify-cache", 2_700 * mb),
        ("slack-cache", 1_300 * mb),
        ("vscode-cache", 900 * mb),
        ("mail-downloads", 1_600 * mb),
        ("trash", 3_400 * mb),
    ]

    @MainActor
    static func prepareDatabase() {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] { try? fm.removeItem(atPath: databasePath + suffix) }
        guard let store = try? Store(path: databasePath) else { return }
        do {
            let rules = try store.beginScan(source: .rule)
            for (id, size) in catalogSizes where size > 0 {
                guard let location = Catalog.locations.first(where: { $0.id == id }) else { continue }
                try store.upsert(finding(from: location, size: size), scanId: rules.id)
            }
            try store.upsert(projects, scanId: rules.id)
            for (id, title, size, command) in [
                ("docker-build-cache", "Docker build cache", 16_900 * mb, "docker builder prune -a -f"),
                ("docker-unused-images", "Unused Docker images", 8_400 * mb, "docker image prune -a -f"),
            ] {
                try store.upsert(Finding(id: id, title: title, paths: [], sizeBytes: size, safety: .safe, source: .rule,
                                         category: .docker,
                                         explanation: "Measured with docker system df. Docker recreates what a build needs again.",
                                         action: .command, command: command,
                                         verification: Verification(rule: id, evidence: "docker system df", measuredByFreeroom: true),
                                         icon: FindingIcon(app: "com.docker.docker", brand: "docker", symbol: "shippingbox")),
                                 scanId: rules.id)
            }
            try store.endScan(id: rules.id)

            let agent = try store.beginScan(source: .agent, note: "Demo", pluginVersion: "0.1.0")
            for finding in agentFindings { try store.upsert(finding, scanId: agent.id) }
            try store.endScan(id: agent.id)

            let day: TimeInterval = 86_400
            for (title, bytes, daysAgo, origin) in [
                ("npm cache", 5_200 * mb, 2.0, "menu"),
                ("Xcode DerivedData", 38_400 * mb, 9.0, "window"),
                ("Homebrew downloads", 2_600 * mb, 16.0, "notification"),
            ] {
                try store.recordCleanup(HistoryEntry(findingId: "demo:\(title)", title: title, freedBytes: bytes,
                                                     at: Date().addingTimeInterval(-daysAgo * day), origin: origin))
            }
        } catch {}
    }

    private static func finding(from location: KnownLocation, size: Int64) -> Finding {
        Finding(id: "catalog:\(location.id)", title: location.title, paths: location.paths, sizeBytes: size,
                safety: location.safety, source: .rule, category: location.category,
                explanation: location.explanation, action: location.action, command: location.command,
                needsAdmin: location.needsAdmin,
                verification: Verification(rule: "catalog:\(location.id)", evidence: "Known location, measured by Freeroom",
                                           measuredByFreeroom: true),
                icon: location.icon)
    }

    private static var projects: Finding {
        let paths = ["~/Projects/web-shop/node_modules", "~/Projects/web-shop/.next",
                     "~/Projects/api-server/target", "~/Projects/ml-notebooks/.venv",
                     "~/Projects/mobile-app/node_modules", "~/Projects/landing/dist"]
        return Finding(id: "projects:build-folders", title: "Build folders in projects (\(paths.count))", paths: paths,
                       sizeBytes: 11_700 * mb, sharedBytes: 1_900 * mb, safety: .safe, source: .rule, category: .projects,
                       explanation: "Dependency and build output folders (node, rust, python). Each one was matched only with evidence, such as a manifest next to it. They are recreated when you install or build the project again.",
                       action: .delete,
                       verification: Verification(rule: "projects:build-folders", evidence: "Manifest next to each folder",
                                                  measuredByFreeroom: true),
                       icon: FindingIcon(symbol: "hammer"))
    }

    private static var agentFindings: [Finding] {
        [
            Finding(id: "agent:old-video-exports", title: "Old screen recordings", paths: ["~/Movies/Exports"],
                    sizeBytes: 18_300 * mb, safety: .review, source: .agent, category: .personal,
                    explanation: "42 screen recordings exported between 2022 and 2023, none opened in the last 18 months. Review them before deleting: they are personal files, not caches.",
                    action: .trash,
                    verification: Verification(rule: "agent", evidence: "Last opened dates checked with mdls", measuredByFreeroom: true),
                    icon: FindingIcon(symbol: "film")),
            Finding(id: "agent:abandoned-project", title: "Abandoned prototype with build caches", paths: ["~/Projects/old-prototype"],
                    sizeBytes: 6_800 * mb, safety: .review, source: .agent, category: .projects,
                    explanation: "Last commit 2 years ago; 6.1 GB of it is a Gradle and node_modules cache. The source code itself is 40 MB and is pushed to its remote.",
                    action: .trash,
                    verification: Verification(rule: "agent", evidence: "git log and remote checked", measuredByFreeroom: true),
                    icon: FindingIcon(symbol: "folder.badge.questionmark")),
        ]
    }
}

extension AppModel {
    /// Shows what FREEROOM_DEMO_ROUTE asks for: findings (default), history, settings, onboarding,
    /// or menu (the menu bar popover).
    func showDemoWindow() {
        let env = ProcessInfo.processInfo.environment
        let route = env["FREEROOM_DEMO_ROUTE"] ?? "findings"
        // -AppleInterfaceStyle does not reach the app's windows; set the appearance directly.
        switch env["FREEROOM_DEMO_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        if route == "menu" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { Demo.clickStatusItem() }
            return
        }
        if onboarded { openMainWindow() } // onboarding opens the window by itself
        guard onboarded else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.expandMainWindow()
            switch route {
            case "history": self.route = .history
            case "settings": self.route = .settings
            default: if !self.simpleMode { self.inspected = "catalog:xcode-derived-data" }
            }
        }
    }
}

extension Demo {
    /// MenuBarExtra has no API to open its popover, so find the status bar button and click it.
    @MainActor
    static func clickStatusItem() {
        func find(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, String(describing: type(of: button)).contains("StatusBar") { return button }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let root = window.contentView, let button = find(root) ?? (root as? NSButton) {
                button.performClick(nil)
                return
            }
        }
    }
}
