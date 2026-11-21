import Foundation

/// The AI-free scan: known locations + tool probes + build folders in project roots.
/// Cheap enough to run periodically from the menu bar app.
public struct RuleEngine: Sendable {
    /// Ignore findings smaller than this.
    public var minimumBytes: Int64
    public var projectRoots: [String]
    public var includeProbes: Bool

    public static let defaultProjectRoots = ["~/Documents", "~/Projects", "~/Developer", "~/code", "~/src", "~/dev", "~/repos"]

    public init(minimumBytes: Int64 = 100_000_000,
                projectRoots: [String] = RuleEngine.defaultProjectRoots,
                includeProbes: Bool = true) {
        self.minimumBytes = minimumBytes
        self.projectRoots = projectRoots
        self.includeProbes = includeProbes
    }

    /// - Parameter onFinding: called with each finding (already above `minimumBytes`) as soon as it
    ///   is measured, so callers can show progress while the slower steps are still running.
    public func run(scanId: String? = nil, onFinding: ((Finding) -> Void)? = nil) -> [Finding] {
        var findings: [Finding] = []
        func emit(_ batch: [Finding]) {
            for var finding in batch where finding.sizeBytes >= minimumBytes {
                finding.scanId = scanId
                findings.append(finding)
                onFinding?(finding)
            }
        }
        for location in Catalog.locations {
            if let finding = catalogFinding(location) { emit([finding]) }
        }
        if includeProbes {
            emit(Probes.simulatorRuntimes())
            emit(Probes.docker())
        }
        if let projects = projectFinding() { emit([projects]) }
        return findings.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    public func catalogFindings() -> [Finding] {
        Catalog.locations.compactMap(catalogFinding)
    }

    private func catalogFinding(_ location: KnownLocation) -> Finding? {
        guard !location.paths.isEmpty else { return nil } // tool-managed: covered by Probes
        let report = Measurer().measure(location.paths)
        let existing = report.items.filter(\.exists)
        guard !existing.isEmpty, report.totalAllocatedBytes > 0 else { return nil }
        return Finding(
            id: "catalog:\(location.id)",
            title: location.title,
            paths: existing.map(\.path),
            sizeBytes: report.totalAllocatedBytes,
            sharedBytes: report.totalSharedBytes,
            safety: location.safety,
            source: .rule,
            category: location.category,
            explanation: location.explanation,
            action: location.action,
            command: location.command,
            needsAdmin: location.needsAdmin,
            verification: Verification(rule: "catalog:\(location.id)",
                                       evidence: "Known location, measured by Freeroom",
                                       measuredByFreeroom: true),
            icon: location.icon
        )
    }

    /// One aggregated finding for all verified build folders (measured together so pnpm
    /// hard links are counted once and links into the shared store are reported as shared).
    public func projectFinding() -> Finding? {
        let roots = projectRoots.map { PathUtils.expand($0) }.filter { FS.isDirectory($0) }
        guard !roots.isEmpty else { return nil }
        let matches = ProjectScanner().scan(roots: roots)
        guard !matches.isEmpty else { return nil }
        let report = Measurer().measure(matches.map(\.path))
        let ecosystems = Set(matches.map(\.ecosystem)).sorted().joined(separator: ", ")
        return Finding(
            id: "projects:build-folders",
            title: "Build folders in projects (\(matches.count))",
            paths: matches.map(\.path),
            sizeBytes: report.totalAllocatedBytes,
            sharedBytes: report.totalSharedBytes,
            safety: .safe,
            source: .rule,
            category: .projects,
            explanation: "Dependency and build output folders (\(ecosystems)). Each one was matched only with evidence, such as a manifest next to it. They are recreated when you install or build the project again.",
            action: .delete,
            verification: Verification(rule: "build-artifacts",
                                       evidence: "\(matches.count) folders matched with evidence (e.g. \(matches[0].evidence))",
                                       measuredByFreeroom: true),
            icon: FindingIcon(symbol: "hammer")
        )
    }
}
