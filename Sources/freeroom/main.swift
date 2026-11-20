import ArgumentParser
import Foundation
import FreeroomCore

// The `freeroom` CLI is the agent's (and power user's) window into Freeroom.
// It measures, classifies and records findings. It deliberately has NO delete command:
// only Freeroom.app deletes, after the user confirms.

struct FreeroomCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "freeroom",
        abstract: "Measure disk usage accurately and record cleanup findings for Freeroom.app.",
        discussion: "All output is JSON. Freeroom never deletes from the CLI: review and clean in Freeroom.app.",
        version: Freeroom.version,
        subcommands: [Status.self, KnownLocations.self, Measure.self, Projects.self, Rules.self,
                      Scan.self, Report.self, Findings.self, Translate.self]
    )
}

// MARK: - Output

func emit<T: Encodable>(_ value: T) throws {
    let data = try JSONEncoder.freeroom.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

struct MeasuredItem: Encodable {
    var path: String
    var exists: Bool
    var allocatedBytes: Int64
    var size: String
    var sharedBytes: Int64
    var reclaimableBytes: Int64
    var reclaimable: String
    var fileCount: Int
    var skippedMounts: [String]
    var unreadableCount: Int
    var children: [Child]?
    struct Child: Encodable { var path: String; var allocatedBytes: Int64; var size: String }

    init(_ m: DiskMeasurement) {
        path = PathUtils.abbreviate(m.path)
        exists = m.exists
        allocatedBytes = m.allocatedBytes
        size = m.allocatedBytes.formattedBytes
        sharedBytes = m.sharedBytes
        reclaimableBytes = m.reclaimableBytes
        reclaimable = m.reclaimableBytes.formattedBytes
        fileCount = m.fileCount
        skippedMounts = m.skippedMounts.map { PathUtils.abbreviate($0) }
        unreadableCount = m.unreadableCount
        children = m.children?.map { Child(path: PathUtils.abbreviate($0.path), allocatedBytes: $0.allocatedBytes,
                                           size: $0.allocatedBytes.formattedBytes) }
    }
}

// MARK: - status

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Version, database, permissions and free space.")

    struct Output: Encodable {
        var version: String
        var database: String
        var fullDiskAccess: Bool
        var freeBytes: Int64
        var free: String
        var totalBytes: Int64
        var appRunning: Bool
        var openAgentScan: String?
        var note: String
    }

    func run() throws {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        // Reading a TCC-protected folder is the standard probe for Full Disk Access.
        let fda = (try? FileManager.default.contentsOfDirectory(atPath: PathUtils.expand("~/Library/Safari"))) != nil
        let appRunning = Shell.run(["pgrep", "-x", "Freeroom"], timeout: 3).ok
        let store = try Store()
        try emit(Output(
            version: Freeroom.version,
            database: PathUtils.abbreviate(store.path),
            fullDiskAccess: fda,
            freeBytes: free, free: free.formattedBytes, totalBytes: total,
            appRunning: appRunning,
            openAgentScan: try store.openScan(source: .agent)?.id,
            note: fda ? "ok" : "Without Full Disk Access some folders are unreadable and sizes may be too low. Grant it to your terminal in System Settings > Privacy & Security."
        ))
    }
}

// MARK: - known-locations

struct KnownLocations: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "known-locations",
        abstract: "Well-known places that grow (caches, toolchains…), measured, with a suggested class.")

    @Flag(help: "Include locations that do not exist on this Mac.") var all = false

    struct Item: Encodable {
        var id: String
        var title: String
        var category: String
        var safety: SafetyClass
        var action: CleanupAction
        var command: String?
        var explanation: String
        var paths: [String]
        var exists: Bool
        var allocatedBytes: Int64
        var size: String
        var sharedBytes: Int64
    }

    func run() throws {
        var items: [Item] = []
        for location in Catalog.locations {
            let report = Measurer().measure(location.paths)
            let exists = report.items.contains(where: \.exists)
            guard exists || all else { continue }
            items.append(Item(id: location.id, title: location.title, category: location.category.rawValue,
                              safety: location.safety, action: location.action, command: location.command,
                              explanation: location.explanation, paths: location.paths, exists: exists,
                              allocatedBytes: report.totalAllocatedBytes, size: report.totalAllocatedBytes.formattedBytes,
                              sharedBytes: report.totalSharedBytes))
        }
        try emit(items.sorted { $0.allocatedBytes > $1.allocatedBytes })
    }
}

// MARK: - measure

struct Measure: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Real size of paths: hard links counted once, other volumes not entered. Use instead of du.")

    @Argument(help: "Paths to measure (measured together, so shared hard links count once).") var paths: [String]
    @Option(help: "Also list the N largest first-level children of each path.") var top = 0

    struct Output: Encodable {
        var items: [MeasuredItem]
        var totalAllocatedBytes: Int64
        var total: String
        var totalSharedBytes: Int64
        var totalReclaimableBytes: Int64
        var totalReclaimable: String
        var notes: [String]
    }

    func run() throws {
        let report = Measurer(topChildren: top).measure(paths)
        var notes: [String] = []
        if report.items.contains(where: { !$0.skippedMounts.isEmpty }) {
            notes.append("Some folders are other mounted volumes and were not counted (e.g. simulator runtimes). Measure the volume itself if needed.")
        }
        if report.totalSharedBytes > 0 {
            notes.append("sharedBytes are hard-linked from outside these paths (e.g. pnpm store). Deleting frees only reclaimableBytes.")
        }
        if report.items.contains(where: { $0.unreadableCount > 0 }) {
            notes.append("Some entries were unreadable; grant Full Disk Access for exact numbers.")
        }
        try emit(Output(items: report.items.map(MeasuredItem.init), totalAllocatedBytes: report.totalAllocatedBytes,
                        total: report.totalAllocatedBytes.formattedBytes, totalSharedBytes: report.totalSharedBytes,
                        totalReclaimableBytes: report.totalReclaimableBytes,
                        totalReclaimable: report.totalReclaimableBytes.formattedBytes, notes: notes))
    }
}

// MARK: - projects

struct Projects: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find regenerable build folders (node_modules, target, .venv…) that match a rule with evidence.")

    @Argument(help: "Roots to search. Defaults to common project folders.") var roots: [String] = []
    @Option(help: "Only list folders at least this many MB.") var minMb = 10

    struct Item: Encodable {
        var path: String
        var rule: String
        var ecosystem: String
        var evidence: String
        var regenerate: String
        var allocatedBytes: Int64
        var size: String
    }

    struct Output: Encodable {
        var roots: [String]
        var count: Int
        var items: [Item]
        var totalAllocatedBytes: Int64
        var total: String
        var totalReclaimableBytes: Int64
        var totalReclaimable: String
    }

    func run() throws {
        let searchRoots = (roots.isEmpty ? RuleEngine.defaultProjectRoots : roots).map { PathUtils.expand($0) }
        let matches = ProjectScanner().scan(roots: searchRoots)
        let combined = Measurer().measure(matches.map(\.path))
        let minBytes = Int64(minMb) * 1_000_000
        let items = zip(matches, combined.items).compactMap { match, m -> Item? in
            guard m.allocatedBytes >= minBytes else { return nil }
            return Item(path: PathUtils.abbreviate(match.path), rule: match.rule, ecosystem: match.ecosystem,
                        evidence: match.evidence, regenerate: match.regenerate,
                        allocatedBytes: m.allocatedBytes, size: m.allocatedBytes.formattedBytes)
        }.sorted { $0.allocatedBytes > $1.allocatedBytes }
        try emit(Output(roots: searchRoots.filter { FileManager.default.fileExists(atPath: $0) }.map { PathUtils.abbreviate($0) },
                        count: matches.count, items: items,
                        totalAllocatedBytes: combined.totalAllocatedBytes, total: combined.totalAllocatedBytes.formattedBytes,
                        totalReclaimableBytes: combined.totalReclaimableBytes,
                        totalReclaimable: combined.totalReclaimableBytes.formattedBytes))
    }
}

// MARK: - rules

struct Rules: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the built-in rule engine (no AI): known locations, Docker, simulators, project build folders.")

    @Flag(help: "Save the result as a rule scan so Freeroom.app shows it.") var save = false
    @Option(help: "Ignore findings smaller than this many MB.") var minMb = 100

    func run() throws {
        var scanId: String?
        let store = save ? try Store() : nil
        if let store { scanId = try store.beginScan(source: .rule).id }
        let findings = RuleEngine(minimumBytes: Int64(minMb) * 1_000_000).run(scanId: scanId)
        if let store, let scanId {
            for finding in findings { try store.upsert(finding, scanId: scanId) }
            try store.endScan(id: scanId)
        }
        try emit(findings.map(DisplayFinding.init))
    }
}

/// Finding with human-readable size and `~` paths, for output.
struct DisplayFinding: Encodable {
    var finding: Finding
    init(_ f: Finding) {
        var copy = f
        copy.paths = f.paths.map { PathUtils.abbreviate($0) }
        finding = copy
    }
    func encode(to encoder: Encoder) throws {
        try finding.encode(to: encoder)
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(finding.sizeBytes.formattedBytes, forKey: .size)
    }
    enum Key: String, CodingKey { case size }
}

// MARK: - scan

struct Scan: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open or close an agent scan session (Freeroom.app shows it live).",
        subcommands: [Begin.self, End.self])

    struct Begin: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Start an agent scan; prints its id.")
        @Option(help: "Free-text note shown in the app.") var note: String?
        func run() throws {
            let store = try Store()
            if let open = try store.openScan(source: .agent) { try store.endScan(id: open.id) }
            try emit(try store.beginScan(source: .agent, note: note))
        }
    }

    struct End: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Finish the open agent scan.")
        func run() throws {
            let store = try Store()
            guard let open = try store.openScan(source: .agent) else { throw Failure("No open agent scan.") }
            try store.endScan(id: open.id)
            let findings = try store.findings(scanId: open.id)
            struct Out: Encodable { var scan: String; var findings: Int; var totalBytes: Int64; var total: String }
            let total = findings.reduce(0) { $0 + $1.sizeBytes }
            try emit(Out(scan: open.id, findings: findings.count, totalBytes: total, total: total.formattedBytes))
        }
    }
}

// MARK: - report

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record a finding from the agent. Freeroom re-measures the paths itself.",
        discussion: """
        Pass one JSON object (or an array) with --json, or on stdin. Fields:
          id (string, stable slug)       title (string)
          paths ([string], may be empty for tool-managed items like Docker)
          safety: safe | review | keep    category: \(FindingCategory.allCases.map(\.rawValue).joined(separator: " | "))
          explanation (English)          action: command | trash | delete | none
          command (string, when action=command)   needsAdmin (bool, optional)
          evidence (string, why this classification is right)
          sizeBytes (only used when paths is empty)
          icon (optional): {"app": "<bundle id>"} or {"brand": "<simple-icons slug>"} or {"symbol": "<SF Symbol>"}
        """)

    @Option(help: "Finding JSON. Reads stdin when omitted.") var json: String?

    struct Input: Decodable {
        var id: String
        var title: String
        var paths: [String]?
        var safety: SafetyClass
        var category: FindingCategory?
        var explanation: String
        var action: CleanupAction?
        var command: String?
        var needsAdmin: Bool?
        var evidence: String?
        var sizeBytes: Int64?
        var icon: FindingIcon?
    }

    func run() throws {
        let text = json ?? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        let data = Data(text.utf8)
        let inputs: [Input]
        if let many = try? JSONDecoder().decode([Input].self, from: data) {
            inputs = many
        } else {
            do { inputs = [try JSONDecoder().decode(Input.self, from: data)] } catch {
                throw Failure("Invalid finding JSON: \(error). Run `freeroom report --help` for the schema.")
            }
        }

        let store = try Store()
        let scan = try store.openScan(source: .agent) ?? store.beginScan(source: .agent, note: "auto")
        var saved: [DisplayFinding] = []
        for input in inputs {
            let paths = (input.paths ?? []).map { PathUtils.expand($0) }
            for path in paths where !FileManager.default.fileExists(atPath: path) {
                throw Failure("Path does not exist: \(PathUtils.abbreviate(path)) (finding \(input.id))")
            }
            if input.action == .command && (input.command ?? "").isEmpty {
                throw Failure("action=command needs a command (finding \(input.id))")
            }
            var size = input.sizeBytes ?? 0
            var shared: Int64 = 0
            if !paths.isEmpty {
                let report = Measurer().measure(paths)
                size = report.totalAllocatedBytes
                shared = report.totalSharedBytes
            }
            let finding = Finding(
                id: "agent:\(input.id)", title: input.title, paths: paths, sizeBytes: size, sharedBytes: shared,
                safety: input.safety, source: .agent, category: input.category ?? .other,
                explanation: input.explanation,
                action: input.action ?? (input.safety == .safe ? .delete : input.safety == .review ? .trash : .none),
                command: input.command, needsAdmin: input.needsAdmin ?? false,
                verification: Verification(rule: "agent", evidence: input.evidence ?? "",
                                           measuredByFreeroom: !paths.isEmpty),
                scanId: scan.id,
                icon: input.icon)
            try store.upsert(finding, scanId: scan.id)
            saved.append(DisplayFinding(finding))
        }
        try emit(saved)
    }
}

// MARK: - findings

struct Findings: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List findings (latest rule and agent scans by default).")
    @Option(help: "Only this scan id.") var scan: String?
    @Option(help: "Show explanations in this language when a translation exists (e.g. es, de).") var lang: String?

    func run() throws {
        let store = try Store()
        var findings = try scan.map { try store.findings(scanId: $0) } ?? store.latestFindings()
        if let lang {
            let translated = try store.translations(lang: lang)
            findings = findings.map { var f = $0; f.explanation = translated[f.id] ?? f.explanation; return f }
        }
        try emit(findings.map(DisplayFinding.init))
    }
}

// MARK: - translate

struct Translate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Store translated explanations. Explanations are written in English; translate only on request.",
        discussion: """
        1) `freeroom findings` to read the English explanations.
        2) Translate them, then: freeroom translate --lang es --json '[{"id":"agent:docker-cache","text":"…"}]'
        """)
    @Option(help: "Target language code, e.g. es, de.") var lang: String
    @Option(help: "JSON array of {id, text}. Reads stdin when omitted.") var json: String?

    struct Item: Decodable { var id: String; var text: String }

    func run() throws {
        let text = json ?? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        let items = try JSONDecoder().decode([Item].self, from: Data(text.utf8))
        let store = try Store()
        for item in items { try store.setTranslation(findingId: item.id, lang: lang, text: item.text) }
        struct Out: Encodable { var lang: String; var saved: Int }
        try emit(Out(lang: lang, saved: items.count))
    }
}

FreeroomCLI.main()
