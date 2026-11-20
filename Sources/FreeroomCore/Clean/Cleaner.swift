import Foundation

public enum CleanupOutcome: Equatable, Sendable {
    case cleaned(freedBytes: Int64)
    /// Not executed on purpose (needs admin, informational, command not on the allowlist…).
    case skipped(reason: String)
    case failed(reason: String)

    public var freedBytes: Int64 {
        if case .cleaned(let bytes) = self { return bytes }
        return 0
    }
}

/// The only component that removes anything. Called by Freeroom.app after the user confirms.
///
/// Safety model — the agent's findings are *suggestions*, never trusted blindly:
/// * Commands run only if they match an allowlist of known cleanup commands, and contain no
///   shell syntax at all (no `;`, `&&`, `|`, `$()`, redirects, quotes). They are executed without a shell.
/// * Paths must be inside the home folder and never be a protected folder (the home itself,
///   standard top-level folders, `~/Library`, credentials). Outside home → skipped.
/// * `needsAdmin` findings are never executed here; the user gets the command to run.
public struct Cleaner: Sendable {
    public struct AllowedCommand: Sendable {
        public let prefix: [String]
        public let maxExtraArguments: Int
    }

    public static let allowedCommands: [AllowedCommand] = [
        .init(prefix: ["docker", "builder", "prune"], maxExtraArguments: 3),
        .init(prefix: ["docker", "buildx", "prune"], maxExtraArguments: 5),
        .init(prefix: ["docker", "image", "prune"], maxExtraArguments: 3),
        .init(prefix: ["xcrun", "simctl", "runtime", "delete"], maxExtraArguments: 1),
        .init(prefix: ["xcrun", "simctl", "erase", "all"], maxExtraArguments: 0),
        .init(prefix: ["xcrun", "simctl", "delete", "unavailable"], maxExtraArguments: 0),
        .init(prefix: ["go", "clean", "-modcache"], maxExtraArguments: 0),
        .init(prefix: ["go", "clean", "-cache"], maxExtraArguments: 0),
        .init(prefix: ["npm", "cache", "clean"], maxExtraArguments: 1),
        .init(prefix: ["pnpm", "store", "prune"], maxExtraArguments: 0),
        .init(prefix: ["yarn", "cache", "clean"], maxExtraArguments: 0),
        .init(prefix: ["pip", "cache", "purge"], maxExtraArguments: 0),
        .init(prefix: ["pip3", "cache", "purge"], maxExtraArguments: 0),
        .init(prefix: ["brew", "cleanup"], maxExtraArguments: 2),
        .init(prefix: ["dotnet", "nuget", "locals", "all", "--clear"], maxExtraArguments: 0),
        .init(prefix: ["ollama", "rm"], maxExtraArguments: 1),
        .init(prefix: ["uv", "cache", "clean"], maxExtraArguments: 0),
        .init(prefix: ["bun", "pm", "cache", "rm"], maxExtraArguments: 0),
        .init(prefix: ["deno", "clean"], maxExtraArguments: 0),
        .init(prefix: ["pod", "cache", "clean", "--all"], maxExtraArguments: 0),
        .init(prefix: ["swift", "package", "purge-cache"], maxExtraArguments: 0),
        .init(prefix: ["conda", "clean", "--all", "--yes"], maxExtraArguments: 0),
        .init(prefix: ["composer", "clear-cache"], maxExtraArguments: 0),
        .init(prefix: ["ccache", "-C"], maxExtraArguments: 0),
        .init(prefix: ["brew", "autoremove"], maxExtraArguments: 0),
        .init(prefix: ["vagrant", "box", "prune"], maxExtraArguments: 0),
        .init(prefix: ["docker", "container", "prune", "-f"], maxExtraArguments: 0),
    ]

    /// Top-level folders (relative to home) that must never be removed as a whole.
    static let protectedRelative: Set<String> = [
        "", "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies", "Music",
        "Pictures", "Public", "Projects", "Developer", "go", ".config", ".local", ".cache",
        "Library/Application Support", "Library/Caches", "Library/Containers", "Library/Group Containers",
        "Library/Preferences", "Library/Developer", "Library/Mobile Documents", "Library/CloudStorage",
    ]

    /// Never touched, nor anything inside them.
    static let forbiddenRelativeTrees: [String] = [
        ".ssh", ".gnupg", "Library/Keychains", ".aws", ".kube", ".docker/contexts",
        "Library/Mail", "Library/Messages", "Library/Mobile Documents", "Library/CloudStorage",
    ]

    public let home: String
    public let fileManager: FileManager

    public init(home: String = NSHomeDirectory(), fileManager: FileManager = .default) {
        self.home = PathUtils.expand(home)
        self.fileManager = fileManager
    }

    // MARK: Validation

    /// Splits a command into arguments, or returns nil if it contains any shell syntax.
    public static func tokenize(_ command: String) -> [String]? {
        let forbidden = CharacterSet(charactersIn: ";&|`$<>(){}[]*?!~\\\"'\n\r\t#=")
        guard command.rangeOfCharacter(from: forbidden) == nil else { return nil }
        let tokens = command.split(separator: " ").map(String.init)
        return tokens.isEmpty ? nil : tokens
    }

    public static func isAllowed(command: String) -> Bool {
        guard let tokens = tokenize(command) else { return false }
        return allowedCommands.contains { allowed in
            tokens.count >= allowed.prefix.count
                && Array(tokens.prefix(allowed.prefix.count)) == allowed.prefix
                && tokens.count - allowed.prefix.count <= allowed.maxExtraArguments
                && tokens.dropFirst(allowed.prefix.count).allSatisfy { arg in
                    // extra arguments: flags or simple identifiers (runtime UUIDs, model names)
                    arg.allSatisfy { $0.isLetter || $0.isNumber || "-_.:".contains($0) }
                }
        }
    }

    /// Returns why a path may not be removed, or nil if it may.
    public func refusal(for rawPath: String) -> String? {
        let path = PathUtils.expand(rawPath)
        guard path.hasPrefix("/") else { return "not an absolute path" }
        guard !path.split(separator: "/").contains("..") else { return "path contains .." }
        guard path.hasPrefix(home + "/") else { return "outside the home folder" }
        let relative = String(path.dropFirst(home.count + 1))
        if Self.protectedRelative.contains(relative) { return "protected folder" }
        for tree in Self.forbiddenRelativeTrees where relative == tree || relative.hasPrefix(tree + "/") {
            return "protected data (\(tree))"
        }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return "no longer exists" }
        return nil
    }

    // MARK: Execution

    public func clean(_ finding: Finding) -> CleanupOutcome {
        if finding.safety == .keep { return .skipped(reason: "classified as keep") }
        if finding.needsAdmin {
            return .skipped(reason: "needs administrator rights; run it yourself: sudo \(finding.command ?? "…")")
        }

        switch finding.action {
        case .none:
            return .skipped(reason: "informational only")

        case .command:
            guard let command = finding.command, let tokens = Self.tokenize(command), Self.isAllowed(command: command) else {
                return .skipped(reason: "command is not on Freeroom's allowlist; run it yourself if you trust it: \(finding.command ?? "")")
            }
            let before = freeSpace()
            let result = Shell.run(tokens, timeout: 900)
            guard result.ok else {
                let message = result.timedOut ? "timed out" : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failed(reason: "\(tokens.joined(separator: " ")): \(message.prefix(300))")
            }
            // Tools free space themselves; report what the disk actually gained, but never more
            // than the finding's size (other apps may have freed space at the same time).
            let gained = max(0, freeSpace() - before)
            return .cleaned(freedBytes: gained > 0 ? min(gained, finding.sizeBytes) : finding.sizeBytes)

        case .delete, .trash:
            guard !finding.paths.isEmpty else { return .skipped(reason: "no paths to remove") }
            for path in finding.paths {
                if let reason = refusal(for: path) { return .skipped(reason: "\(PathUtils.abbreviate(path)): \(reason)") }
            }
            let measured = Measurer().measure(finding.paths).totalReclaimableBytes
            do {
                for path in finding.paths {
                    let url = URL(fileURLWithPath: PathUtils.expand(path))
                    if url.path == home + "/.Trash" {
                        try emptyTrash(url)
                    } else if finding.action == .trash {
                        try fileManager.trashItem(at: url, resultingItemURL: nil)
                    } else {
                        try fileManager.removeItem(at: url)
                    }
                }
            } catch {
                return .failed(reason: error.localizedDescription)
            }
            return .cleaned(freedBytes: measured)
        }
    }

    private func emptyTrash(_ url: URL) throws {
        for item in try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: item)
        }
    }

    public func freeSpace() -> Int64 {
        let values = try? URL(fileURLWithPath: home).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
