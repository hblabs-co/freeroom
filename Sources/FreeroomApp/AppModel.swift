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

    // Findings (latest rule scan + latest agent scan, minus what was already cleaned)
    var findings: [Finding] = []
    var translations: [String: String] = [:]
    var lastRuleScan: ScanRecord?
    var lastAgentScan: ScanRecord?
    var agentScanLive: Bool { lastAgentScan != nil && lastAgentScan?.endedAt == nil }
    var isRunningRules = false
    var storeError: String?

    // Selection & cleaning
    var selection: Set<String> = []
    var cleaning = false
    var cleanResults: [String: CleanupOutcome] = [:]
    var history: [HistoryEntry] = []

    // Settings (persisted in UserDefaults)
    var language: String { didSet { defaults.set(language, forKey: "language"); reload() } }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notifications") } }
    var lowDiskThresholdGB: Int { didSet { defaults.set(lowDiskThresholdGB, forKey: "lowDiskGB") } }
    var checkEveryHours: Int { didSet { defaults.set(checkEveryHours, forKey: "checkHours"); scheduleRuleChecks() } }
    var showFreeInMenuBar: Bool { didSet { defaults.set(showFreeInMenuBar, forKey: "menuBarFree") } }

    private let defaults = UserDefaults.standard
    private var store: Store?
    private var pollTimer: Timer?
    private var ruleTimer: Timer?

    init() {
        language = defaults.string(forKey: "language") ?? "en"
        notificationsEnabled = defaults.object(forKey: "notifications") as? Bool ?? true
        lowDiskThresholdGB = defaults.object(forKey: "lowDiskGB") as? Int ?? 15
        checkEveryHours = defaults.object(forKey: "checkHours") as? Int ?? 6
        showFreeInMenuBar = defaults.object(forKey: "menuBarFree") as? Bool ?? true

        do { store = try Store() } catch { storeError = "\(error)" }
        reload()
        // The CLI writes while Claude Code scans; poll the small SQLite store to show it live.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        scheduleRuleChecks()
        if notificationsEnabled { requestNotificationPermission() }
        if lastRuleScan == nil { runRules() }
    }

    // MARK: Loading

    func reload() {
        updateDisk()
        guard let store else { return }
        do {
            let scans = try store.scans(limit: 50)
            lastRuleScan = scans.first { $0.source == .rule }
            lastAgentScan = scans.first { $0.source == .agent }
            history = try store.history(limit: 200)
            let cleaned = Dictionary(history.map { ($0.findingId, $0.at) }, uniquingKeysWith: max)
            let scanStart = Dictionary(scans.map { ($0.id, $0.startedAt) }, uniquingKeysWith: { a, _ in a })
            findings = try store.latestFindings().filter { finding in
                guard let at = cleaned[finding.id], let start = finding.scanId.flatMap({ scanStart[$0] }) else { return true }
                return at < start // cleaned before this scan found it again → still relevant
            }
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
        translations[finding.id] ?? finding.explanation
    }

    // MARK: Derived

    var suggestions: [Finding] {
        findings.filter { $0.safety == .safe && $0.action != .none && !$0.needsAdmin }.prefix(3).map { $0 }
    }

    func total(_ safety: SafetyClass) -> Int64 {
        findings.filter { $0.safety == safety }.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedFindings: [Finding] { findings.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedFindings.reduce(0) { $0 + $1.sizeBytes - $1.sharedBytes } }

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
                                                           freedBytes: freed, at: Date(), origin: origin))
                }
                await MainActor.run { self.cleanResults[finding.id] = outcome }
            }
            await MainActor.run {
                self.cleaning = false
                self.selection = []
                self.reload()
            }
        }
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
        let safeTotal = total(.safe)
        if freeBytes < Int64(lowDiskThresholdGB) * 1_000_000_000 {
            content.title = "Disk almost full: \(freeBytes.formattedBytes) free"
            content.body = "\(safeTotal.formattedBytes) can be freed safely. Open Freeroom to review."
        } else if let top = suggestions.first, top.sizeBytes > 5_000_000_000 {
            content.title = "\(top.title): \(top.sizeBytes.formattedBytes)"
            content.body = "\(explanation(for: top)) Review it in Freeroom."
        } else {
            return
        }
        content.sound = nil
        let request = UNNotificationRequest(identifier: "freeroom-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        defaults.set(Date(), forKey: "lastNotification")
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                storeError = "Launch at login: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Helpers

    func copyScanCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("/freeroom:scan", forType: .string)
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
