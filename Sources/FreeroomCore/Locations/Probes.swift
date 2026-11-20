import Foundation

/// Runs a command with a timeout and an extended PATH (GUI apps start with a minimal PATH).
public enum Shell {
    public struct Result: Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String
        public var timedOut: Bool
        public var ok: Bool { status == 0 && !timedOut }
    }

    public static var searchPath: String {
        let home = NSHomeDirectory()
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/go/bin",
                     "/Applications/Docker.app/Contents/Resources/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let current = ProcessInfo.processInfo.environment["PATH"].map { [$0] } ?? []
        return (current + extra).joined(separator: ":")
    }

    public static func run(_ arguments: [String], timeout: TimeInterval = 20) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do { try process.run() } catch {
            return Result(status: -1, stdout: "", stderr: "\(error)", timedOut: false)
        }

        // Read pipes concurrently so a chatty process cannot block on a full pipe.
        nonisolated(unsafe) var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        let timedOut = process.isRunning
        if timedOut { process.terminate() }
        process.waitUntilExit()
        group.wait()

        return Result(status: process.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self),
                      timedOut: timedOut)
    }
}

/// Findings that need a tool's own view of the world instead of a folder size.
public enum Probes {

    // MARK: Xcode simulator runtimes

    struct SimRuntime: Decodable {
        let identifier: String
        let version: String?
        let build: String?
        let platformIdentifier: String?
        let sizeBytes: Int64?
        let lastUsedAt: String?
        let deletable: Bool?
    }

    /// Keeps the most recently used runtime per platform; every other deletable runtime is `safe`.
    /// Sizes come from `simctl` (the disk image), never from the mounted volume, which would double count.
    public static func simulatorRuntimes(json: String? = nil) -> [Finding] {
        let raw: String
        if let json { raw = json } else {
            let result = Shell.run(["xcrun", "simctl", "runtime", "list", "-j"], timeout: 30)
            guard result.ok else { return [] }
            raw = result.stdout
        }
        guard let data = raw.data(using: .utf8),
              let runtimes = try? JSONDecoder().decode([String: SimRuntime].self, from: data)
        else { return [] }

        let byPlatform = Dictionary(grouping: runtimes.values) { $0.platformIdentifier ?? "unknown" }
        var findings: [Finding] = []
        for (platform, list) in byPlatform {
            let sorted = list.sorted { ($0.lastUsedAt ?? "") > ($1.lastUsedAt ?? "") }
            let platformName = platformLabel(platform)
            for runtime in sorted.dropFirst() where runtime.deletable ?? false {
                let kept = sorted[0]
                let name = "\(platformName) \(runtime.version ?? "?") (\(runtime.build ?? runtime.identifier))"
                findings.append(Finding(
                    id: "sim-runtime-\(runtime.identifier)",
                    title: "Simulator runtime \(name)",
                    paths: [],
                    sizeBytes: runtime.sizeBytes ?? 0,
                    safety: .safe,
                    source: .rule,
                    category: .xcode,
                    explanation: "Older \(platformName) simulator runtime. You keep \(platformName) \(kept.version ?? "?"), the one used most recently. Xcode can download this one again.",
                    action: .command,
                    command: "xcrun simctl runtime delete \(runtime.identifier)",
                    needsAdmin: false,
                    verification: Verification(
                        rule: "sim-runtime-not-latest",
                        evidence: "Last used \(runtime.lastUsedAt ?? "never"); newer runtime kept: \(kept.version ?? "?")",
                        measuredByFreeroom: false),
                    icon: FindingIcon(app: "com.apple.dt.Xcode", brand: "xcode", symbol: "iphone")
                ))
            }
        }
        return findings.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func platformLabel(_ id: String) -> String {
        if id.contains("iphone") { return "iOS" }
        if id.contains("watch") { return "watchOS" }
        if id.contains("appletv") { return "tvOS" }
        if id.contains("xr") { return "visionOS" }
        return id
    }

    // MARK: Docker

    struct DockerDF: Decodable {
        let type: String
        let reclaimable: String
        enum CodingKeys: String, CodingKey { case type = "Type", reclaimable = "Reclaimable" }
    }

    /// Parses `docker system df --format '{{json .}}'`. Returns nothing if Docker is not running.
    public static func docker(output: String? = nil) -> [Finding] {
        let raw: String
        if let output { raw = output } else {
            let result = Shell.run(["docker", "system", "df", "--format", "{{json .}}"], timeout: 20)
            guard result.ok else { return [] }
            raw = result.stdout
        }
        var findings: [Finding] = []
        for line in raw.split(separator: "\n") {
            guard let row = try? JSONDecoder().decode(DockerDF.self, from: Data(line.utf8)) else { continue }
            let bytes = parseDockerSize(row.reclaimable)
            guard bytes > 0 else { continue }
            switch row.type {
            case "Build Cache":
                findings.append(dockerFinding(id: "docker-build-cache", title: "Docker build cache", bytes: bytes,
                    explanation: "Layer cache from image builds that no running build uses. Rebuilt on the next build (the first one will be slower).",
                    command: "docker builder prune -a -f", rule: "docker-df-build-cache"))
            case "Images":
                findings.append(dockerFinding(id: "docker-unused-images", title: "Unused Docker images", bytes: bytes,
                    explanation: "Images not used by any container. Pulled or rebuilt again when needed.",
                    command: "docker image prune -a -f", rule: "docker-df-images"))
            case "Local Volumes":
                findings.append(Finding(
                    id: "docker-unused-volumes", title: "Unused Docker volumes", paths: [], sizeBytes: bytes,
                    safety: .review, source: .rule, category: .docker,
                    explanation: "Volumes not attached to any container. They can hold databases: check them before removing.",
                    action: .none, command: "docker volume ls -f dangling=true",
                    verification: Verification(rule: "docker-df-volumes", evidence: "docker system df: reclaimable \(row.reclaimable)",
                                               measuredByFreeroom: false),
                    icon: Self.dockerIcon))
            default:
                continue
            }
        }
        return findings
    }

    private static func dockerFinding(id: String, title: String, bytes: Int64, explanation: String,
                                      command: String, rule: String) -> Finding {
        Finding(id: id, title: title, paths: [], sizeBytes: bytes, safety: .safe, source: .rule,
                category: .docker, explanation: explanation + " Docker Desktop returns the space to macOS gradually.",
                action: .command, command: command,
                verification: Verification(rule: rule, evidence: "Reported reclaimable by `docker system df`",
                                           measuredByFreeroom: false),
                icon: dockerIcon)
    }

    static let dockerIcon = FindingIcon(app: "com.docker.docker", brand: "docker", symbol: "shippingbox")

    /// "5.104GB", "1.522GB (77%)", "40.96kB", "0B" → bytes (Docker uses decimal units).
    public static func parseDockerSize(_ text: String) -> Int64 {
        let token = text.split(separator: " ").first.map(String.init) ?? ""
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (suffix, factor) in units where token.hasSuffix(suffix) {
            guard let value = Double(token.dropLast(suffix.count)) else { return 0 }
            return Int64(value * factor)
        }
        return 0
    }
}
