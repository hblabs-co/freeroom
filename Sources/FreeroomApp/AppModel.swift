import AppKit
import FreeroomCore
import Observation
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class AppModel {
    // Disk
    var freeBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var usedFraction: Double { totalBytes > 0 ? 1 - Double(freeBytes) / Double(totalBytes) : 0 }
    var lowOnSpace: Bool { freeBytes > 0 && freeBytes < Int64(lowDiskThresholdGB) * 1_000_000_000 }

    // Findings: latest rule scan + latest agent scan, minus what was already cleaned, biggest first.
    var findings: [Finding] = []
    var translations: [String: String] = [:]
    var lastRuleScan: ScanRecord?
    var lastAgentScan: ScanRecord?
    var agentScanLive: Bool { lastAgentScan != nil && lastAgentScan?.endedAt == nil }
    /// Ids that appeared in the last reload (for the "new finding" highlight).
    var freshIds: Set<String> = []
    var isRunningRules = false
    var storeError: String?

    // Selection & cleaning
    var selection: Set<String> = []
    var inspected: String?
    /// When set, the main window presents the clean sheet with these findings.
    var pendingClean: [Finding]?
    var cleaning = false
    var cleanResults: [String: CleanupOutcome] = [:]
    var history: [HistoryEntry] = []
    var freedAllTime: Int64 { history.reduce(0) { $0 + $1.freedBytes } }

    // Settings (UserDefaults)
    var language: String { didSet { defaults.set(language, forKey: "language"); L10n.current = language; reload() } }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notifications") } }
    var lowDiskThresholdGB: Int { didSet { defaults.set(lowDiskThresholdGB, forKey: "lowDiskGB") } }
    var checkEveryHours: Int { didSet { defaults.set(checkEveryHours, forKey: "checkHours"); scheduleRuleChecks() } }
    var showFreeInMenuBar: Bool { didSet { defaults.set(showFreeInMenuBar, forKey: "menuBarFree") } }
    var showDiskMap: Bool { didSet { defaults.set(showDiskMap, forKey: "diskMap") } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: "sound") } }
    var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    var simpleMode: Bool { didSet { defaults.set(simpleMode, forKey: "simpleMode") } }
    var textSize: FontScale.Size { didSet { defaults.set(textSize.rawValue, forKey: "textSize"); FontScale.factor = textSize.factor } }
    /// Changes when language or text size change, to rebuild the view tree.
    var appearanceKey: String { "\(language)-\(textSize.rawValue)" }

    /// What the single main window shows.
    enum Route: Hashable { case findings, history, settings }
    var route: Route = .findings

    private let defaults = UserDefaults.standard
    private var store: Store?
    private var pollTimer: Timer?
    private var ruleTimer: Timer?
    private let notificationDelegate = NotificationDelegate()

    init() {
        let savedLanguage = defaults.string(forKey: "language") ?? L10n.preferredSystemLanguage
        language = savedLanguage
        L10n.current = savedLanguage
        notificationsEnabled = defaults.object(forKey: "notifications") as? Bool ?? true
        lowDiskThresholdGB = defaults.object(forKey: "lowDiskGB") as? Int ?? 25
        checkEveryHours = defaults.object(forKey: "checkHours") as? Int ?? 6
        showFreeInMenuBar = defaults.object(forKey: "menuBarFree") as? Bool ?? true
        showDiskMap = defaults.object(forKey: "diskMap") as? Bool ?? true
        playSound = defaults.object(forKey: "sound") as? Bool ?? true
        onboarded = defaults.bool(forKey: "onboarded")
        simpleMode = defaults.object(forKey: "simpleMode") as? Bool ?? true
        let savedSize = FontScale.Size(rawValue: defaults.string(forKey: "textSize") ?? "") ?? .medium
        textSize = savedSize
        FontScale.factor = savedSize.factor

        do { store = try Store() } catch { storeError = "\(error)" }
        reload()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        scheduleRuleChecks()
        notificationDelegate.model = self
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        center.setNotificationCategories([NotificationDelegate.category])
        if onboarded && lastRuleScan == nil { runRules() }
    }

    // MARK: Loading

    func reload() {
        updateDisk()
        guard let store else { return }
        do {
            let scans = try store.scans(limit: 50)
            lastRuleScan = scans.first { $0.source == .rule }
            lastAgentScan = scans.first { $0.source == .agent }
            history = try store.history(limit: 500)
            let cleaned = Dictionary(history.map { ($0.findingId, $0.at) }, uniquingKeysWith: max)
            let scanStart = Dictionary(scans.map { ($0.id, $0.startedAt) }, uniquingKeysWith: { a, _ in a })
            let loaded = try store.latestFindings().filter { finding in
                guard let at = cleaned[finding.id], let start = finding.scanId.flatMap({ scanStart[$0] }) else { return true }
                return at < start
            }.sorted { $0.sizeBytes > $1.sizeBytes }
            let previous = Set(findings.map(\.id))
            if !previous.isEmpty { freshIds = Set(loaded.map(\.id)).subtracting(previous) }
            if loaded != findings { findings = loaded }
            translations = language == "en" ? [:] : try store.translations(lang: language)
            selection = selection.filter { id in findings.contains { $0.id == id } }
        } catch {
            storeError = "\(error)"
        }
    }

    func updateDisk() {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        freeBytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
        totalBytes = Int64(values?.volumeTotalCapacity ?? 0)
    }

    func explanation(for finding: Finding) -> String {
        translations[finding.id]
            ?? Catalog.translation(forFindingId: finding.id, lang: language)?.explanation
            ?? finding.explanation
    }

    // MARK: Derived

    var safeFindings: [Finding] { findings.filter { $0.safety == .safe && $0.isCleanable && !$0.needsAdmin } }
    var suggestions: [Finding] { Array(safeFindings.prefix(3)) }

    func total(_ safety: SafetyClass) -> Int64 {
        findings.filter { $0.safety == safety }.reduce(0) { $0 + $1.reclaimable }
    }

    var cleanableTotal: Int64 { findings.filter(\.isCleanable).reduce(0) { $0 + $1.reclaimable } }
    var selectedFindings: [Finding] { findings.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedFindings.reduce(0) { $0 + $1.reclaimable } }

    var ecosystems: [(Ecosystem, Int64)] {
        Dictionary(grouping: findings, by: \.ecosystem)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.reclaimable }) }
            .sorted { $0.1 > $1.1 }
    }

    func finding(id: String) -> Finding? { findings.first { $0.id == id } }

    // MARK: Rule engine (no AI)

    func runRules() {
        guard !isRunningRules else { return }
        isRunningRules = true
        Task.detached(priority: .utility) {
            let findings = RuleEngine().run()
            do {
                let store = try Store()
                let scan = try store.beginScan(source: .rule)
                for finding in findings { try store.upsert(finding, scanId: scan.id) }
                try store.endScan(id: scan.id)
            } catch {}
            await MainActor.run {
                self.isRunningRules = false
                self.reload()
                self.notifyIfUseful()
            }
        }
    }

    private func scheduleRuleChecks() {
        ruleTimer?.invalidate()
        ruleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(checkEveryHours * 3600), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runRules() }
        }
    }

    // MARK: Cleaning

    func requestClean(_ items: [Finding]) {
        let cleanable = items.filter(\.isCleanable)
        guard !cleanable.isEmpty else { return }
        cleanResults = [:]
        pendingClean = cleanable
        openMainWindow()
    }

    func clean(_ toClean: [Finding], origin: String) {
        guard !cleaning else { return }
        cleaning = true
        cleanResults = [:]
        Task.detached(priority: .userInitiated) {
            let cleaner = Cleaner()
            let store = try? Store()
            for finding in toClean {
                let outcome = cleaner.clean(finding)
                if case .cleaned(let freed) = outcome {
                    try? store?.recordCleanup(HistoryEntry(findingId: finding.id, title: finding.title,
                                                           freedBytes: freed, at: Date(), origin: origin,
                                                           finding: finding))
                }
                await MainActor.run {
                    withAnimation(.smooth) { self.cleanResults[finding.id] = outcome }
                }
            }
            await MainActor.run {
                self.cleaning = false
                self.selection = []
                self.updateDisk()
                if self.playSound { NSSound(named: "Glass")?.play() }
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
    }

    func finishClean() {
        pendingClean = nil
        cleanResults = [:]
        reload()
    }

    // MARK: Notifications (rule engine only, max one per day)

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyIfUseful() {
        guard notificationsEnabled else { return }
        let lastSent = defaults.object(forKey: "lastNotification") as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastSent) > 20 * 3600 else { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = NotificationDelegate.categoryId
        var attachmentIcon: FindingIcon?
        if lowOnSpace {
            content.title = String(format: L("Disk almost full · %@ free"), freeBytes.formattedBytes)
            content.body = String(format: L("%@ can be freed safely."), total(.safe).formattedBytes)
            attachmentIcon = FindingIcon(symbol: "internaldrive")
            content.userInfo = ["action": "safe"]
        } else if let top = suggestions.first, top.sizeBytes > 5_000_000_000 {
            content.title = "\(top.displayTitle) · \(top.sizeBytes.formattedBytes)"
            content.body = String(format: L("Safe: %@"), explanation(for: top))
            attachmentIcon = top.icon
            content.userInfo = ["findingId": top.id]
        } else {
            return
        }
        if let icon = attachmentIcon, let attachment = NotificationDelegate.attachment(for: icon) {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(identifier: "freeroom-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        defaults.set(Date(), forKey: "lastNotification")
    }

    func handleNotification(userInfo: [AnyHashable: Any]) {
        if let id = userInfo["findingId"] as? String, let finding = finding(id: id) {
            requestClean([finding])
        } else if userInfo["action"] as? String == "safe" {
            requestClean(safeFindings)
        } else {
            openMainWindow()
        }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                storeError = "\(L("Launch at login")): \(error.localizedDescription)"
            }
        }
    }

    // MARK: Environment checks (onboarding)

    var hasFullDiskAccess: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: PathUtils.expand("~/Library/Safari"))) != nil
    }

    func pluginInstalled() async -> Bool {
        await Task.detached {
            let result = Shell.run(["claude", "plugin", "list"], timeout: 15)
            return result.ok && result.stdout.contains("freeroom")
        }.value
    }

    // MARK: Helpers

    var openWindowAction: ((String) -> Void)?

    func openMainWindow() {
        openWindowAction?("main")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// After onboarding: grow the compact window to the full app size, centered, animated.
    func expandMainWindow() {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0.title == "Freeroom" })
                ?? NSApp.keyWindow, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: min(1240, visible.width - 40), height: min(800, visible.height - 40))
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
    }

    func openSettings() {
        route = .settings
        openMainWindow()
    }

    func copyScanCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("/freeroom:scan", forType: .string)
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: PathUtils.expand("~/.Trash")))
    }
}

/// Handles notification actions: "Review" opens the clean sheet for that item; "Later" does nothing.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let categoryId = "finding"
    static let category = UNNotificationCategory(
        identifier: categoryId,
        actions: [
            UNNotificationAction(identifier: "review", title: L("Review"), options: [.foreground]),
            UNNotificationAction(identifier: "later", title: L("Later"), options: []),
        ],
        intentIdentifiers: [])

    weak var model: AppModel?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        Task { @MainActor in
            if action != "later" { self.model?.handleNotification(userInfo: info) }
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    /// Renders the item's icon to a PNG so the banner shows it.
    @MainActor
    static func attachment(for icon: FindingIcon) -> UNNotificationAttachment? {
        let renderer = ImageRenderer(content: ItemIcon(icon: icon, size: 128).padding(8))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("freeroom-\(UUID().uuidString).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "icon", url: url)
    }
}
