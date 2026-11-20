import Darwin
import Foundation

/// A rule that recognises a regenerable build/dependency folder inside a project,
/// but only when there is *evidence* that it really is one (a manifest next to it, a marker inside).
public struct BuildArtifactRule: Sendable {
    public let id: String
    public let directoryName: String
    public let ecosystem: String
    public let regenerate: String
    /// Returns human-readable evidence if the folder at `dir` (inside `parent`) matches.
    let check: @Sendable (_ dir: String, _ parent: String) -> String?

    public init(id: String, directoryName: String, ecosystem: String, regenerate: String,
                check: @escaping @Sendable (_ dir: String, _ parent: String) -> String?) {
        self.id = id
        self.directoryName = directoryName
        self.ecosystem = ecosystem
        self.regenerate = regenerate
        self.check = check
    }
}

public struct ArtifactMatch: Codable, Equatable, Sendable {
    public var path: String
    public var rule: String
    public var ecosystem: String
    public var evidence: String
    public var regenerate: String
}

enum FS {
    static func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    static func isDirectory(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// First file in `dir` whose name has one of the given extensions.
    static func firstFile(in dir: String, withExtensions exts: [String]) -> String? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        return names.sorted().first { name in exts.contains { name.hasSuffix("." + $0) } }
    }
}

public extension BuildArtifactRule {
    private static func sibling(_ manifest: String) -> @Sendable (String, String) -> String? {
        { _, parent in FS.exists(parent + "/" + manifest) ? "\(manifest) next to it" : nil }
    }

    private static func anySibling(_ manifests: [String]) -> @Sendable (String, String) -> String? {
        { _, parent in
            manifests.first { FS.exists(parent + "/" + $0) }.map { "\($0) next to it" }
        }
    }

    private static let dotnetProject: @Sendable (String, String) -> String? = { _, parent in
        FS.firstFile(in: parent, withExtensions: ["csproj", "fsproj", "vbproj"]).map { "\($0) next to it" }
    }

    static let all: [BuildArtifactRule] = [
        .init(id: "node-modules", directoryName: "node_modules", ecosystem: "Node.js",
              regenerate: "npm install / pnpm install / yarn", check: sibling("package.json")),
        .init(id: "next-build", directoryName: ".next", ecosystem: "Next.js",
              regenerate: "next build / next dev", check: sibling("package.json")),
        .init(id: "nuxt-build", directoryName: ".nuxt", ecosystem: "Nuxt",
              regenerate: "nuxt build / nuxt dev", check: sibling("package.json")),
        .init(id: "svelte-kit", directoryName: ".svelte-kit", ecosystem: "SvelteKit",
              regenerate: "vite dev / vite build", check: sibling("package.json")),
        .init(id: "turbo-cache", directoryName: ".turbo", ecosystem: "Turborepo",
              regenerate: "turbo run …", check: sibling("package.json")),
        .init(id: "js-dist", directoryName: "dist", ecosystem: "JavaScript build",
              regenerate: "npm run build", check: sibling("package.json")),
        .init(id: "rust-target", directoryName: "target", ecosystem: "Rust",
              regenerate: "cargo build", check: sibling("Cargo.toml")),
        .init(id: "maven-target", directoryName: "target", ecosystem: "Maven",
              regenerate: "mvn package", check: sibling("pom.xml")),
        .init(id: "gradle-build", directoryName: "build", ecosystem: "Gradle",
              regenerate: "gradle build",
              check: anySibling(["build.gradle", "build.gradle.kts"])),
        .init(id: "swiftpm-build", directoryName: ".build", ecosystem: "Swift Package Manager",
              regenerate: "swift build", check: sibling("Package.swift")),
        .init(id: "cocoapods", directoryName: "Pods", ecosystem: "CocoaPods",
              regenerate: "pod install", check: sibling("Podfile")),
        .init(id: "python-venv", directoryName: ".venv", ecosystem: "Python",
              regenerate: "python -m venv .venv && pip install -r requirements.txt",
              check: { dir, _ in FS.exists(dir + "/pyvenv.cfg") ? "pyvenv.cfg inside" : nil }),
        .init(id: "python-venv", directoryName: "venv", ecosystem: "Python",
              regenerate: "python -m venv venv && pip install -r requirements.txt",
              check: { dir, _ in FS.exists(dir + "/pyvenv.cfg") ? "pyvenv.cfg inside" : nil }),
        .init(id: "dotnet-obj", directoryName: "obj", ecosystem: ".NET",
              regenerate: "dotnet restore / dotnet build", check: dotnetProject),
        .init(id: "dotnet-bin", directoryName: "bin", ecosystem: ".NET",
              regenerate: "dotnet build", check: dotnetProject),
    ]
}

/// Walks project folders and returns build artifacts that match a rule *with evidence*.
/// Matched folders are not entered (no nested matches), and `.git` is skipped.
public struct ProjectScanner: Sendable {
    public var rules: [BuildArtifactRule]
    /// Folder names never entered while searching.
    public var skipNames: Set<String> = [".git", ".hg", ".svn", "Library", ".Trash"]

    public init(rules: [BuildArtifactRule] = BuildArtifactRule.all) {
        self.rules = rules
    }

    public func scan(roots: [String]) -> [ArtifactMatch] {
        let byName = Dictionary(grouping: rules, by: \.directoryName)
        var matches: [ArtifactMatch] = []

        for root in roots.map { PathUtils.expand($0) } {
            var rootStat = stat()
            guard lstat(root, &rootStat) == 0 else { continue }
            var cPaths: [UnsafeMutablePointer<CChar>?] = [strdup(root), nil]
            defer { cPaths.forEach { free($0) } }
            guard let fts = fts_open(&cPaths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_NOSTAT, nil) else { continue }
            defer { fts_close(fts) }

            while let entry = fts_read(fts) {
                guard Int32(entry.pointee.fts_info) == FTS_D, entry.pointee.fts_level > 0 else { continue }
                let path = String(cString: entry.pointee.fts_path)
                let name = (path as NSString).lastPathComponent

                if skipNames.contains(name) {
                    fts_set(fts, entry, FTS_SKIP)
                    continue
                }
                guard let candidates = byName[name] else { continue }
                let parent = (path as NSString).deletingLastPathComponent
                for rule in candidates {
                    if let evidence = rule.check(path, parent) {
                        matches.append(ArtifactMatch(path: path, rule: rule.id, ecosystem: rule.ecosystem,
                                                     evidence: evidence, regenerate: rule.regenerate))
                        fts_set(fts, entry, FTS_SKIP)
                        break
                    }
                }
            }
        }
        return matches
    }
}
