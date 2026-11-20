import FreeroomCore
import SwiftUI

/// Groups findings the way developers think about them: by ecosystem, each with its own logo.
struct Ecosystem: Hashable, Identifiable {
    let id: String
    let title: String
    let icon: FindingIcon

    static let docker = Ecosystem(id: "docker", title: "Docker", icon: .init(app: "com.docker.docker", brand: "docker", symbol: "shippingbox"))
    static let xcode = Ecosystem(id: "xcode", title: "Xcode & Simulators", icon: .init(app: "com.apple.dt.Xcode", brand: "xcode", symbol: "hammer"))
    static let javascript = Ecosystem(id: "js", title: "JavaScript", icon: .init(brand: "nodedotjs", symbol: "curlybraces"))
    static let python = Ecosystem(id: "python", title: "Python", icon: .init(brand: "python", symbol: "chevron.left.forwardslash.chevron.right"))
    static let rust = Ecosystem(id: "rust", title: "Rust", icon: .init(brand: "rust", symbol: "gearshape.2"))
    static let go = Ecosystem(id: "go", title: "Go", icon: .init(brand: "go", symbol: "chevron.left.forwardslash.chevron.right"))
    static let jvm = Ecosystem(id: "jvm", title: "Java & Gradle", icon: .init(brand: "gradle", symbol: "cup.and.saucer"))
    static let dotnet = Ecosystem(id: "dotnet", title: ".NET", icon: .init(brand: "dotnet", symbol: "chevron.left.forwardslash.chevron.right"))
    static let ai = Ecosystem(id: "ai", title: "AI models", icon: .init(app: "com.electron.ollama", brand: "ollama", symbol: "brain"))
    static let homebrew = Ecosystem(id: "brew", title: "Homebrew", icon: .init(brand: "homebrew", symbol: "mug"))
    static let projects = Ecosystem(id: "projects", title: "Project builds", icon: .init(symbol: "hammer"))
    static let apps = Ecosystem(id: "apps", title: "App caches", icon: .init(symbol: "square.stack.3d.up"))
    static let personal = Ecosystem(id: "personal", title: "Personal files", icon: .init(symbol: "person.crop.square"))
    static let system = Ecosystem(id: "system", title: "System", icon: .init(symbol: "gearshape"))
    static let other = Ecosystem(id: "other", title: "Other", icon: .init(symbol: "questionmark.folder"))

    private static let brands: [String: Ecosystem] = [
        "docker": .docker, "podman": .docker, "kubernetes": .docker, "helm": .docker,
        "xcode": .xcode, "swift": .xcode, "cocoapods": .xcode, "apple": .xcode,
        "nodedotjs": .javascript, "npm": .javascript, "pnpm": .javascript, "yarn": .javascript, "bun": .javascript,
        "deno": .javascript, "typescript": .javascript, "electron": .javascript, "puppeteer": .javascript,
        "cypress": .javascript, "playwright": .javascript,
        "python": .python, "uv": .python, "anaconda": .python, "poetry": .python, "pypi": .python, "jupyter": .python,
        "rust": .rust, "go": .go,
        "gradle": .jvm, "apachemaven": .jvm, "openjdk": .jvm, "kotlin": .jvm, "scala": .jvm, "android": .jvm, "androidstudio": .jvm,
        "dotnet": .dotnet, "nuget": .dotnet,
        "ollama": .ai, "huggingface": .ai, "pytorch": .ai, "openai": .ai,
        "homebrew": .homebrew,
    ]

    static func of(_ finding: Finding) -> Ecosystem {
        if let brand = finding.icon?.brand, let eco = brands[brand] { return eco }
        if finding.id.contains("docker") { return .docker }
        switch finding.category {
        case .docker: return .docker
        case .xcode: return .xcode
        case .projects: return .projects
        case .appCaches, .apps: return .apps
        case .personal: return .personal
        case .system: return .system
        case .devCaches, .other: return .other
        }
    }
}

extension Finding {
    var ecosystem: Ecosystem { Ecosystem.of(self) }

    /// The short gray line next to the title in a row.
    var meta: String {
        if id == "projects:build-folders" { return "\(paths.count) folders" }
        if action == .command, let tool = command?.split(separator: " ").first { return "\(tool) cleanup" }
        if paths.count > 1 { return "\(paths.count) locations" }
        if let path = paths.first { return (path as NSString).lastPathComponent }
        return ""
    }

    /// Bytes this finding would actually free.
    var reclaimable: Int64 { max(0, sizeBytes - sharedBytes) }
    var isCleanable: Bool { safety != .keep && action != .none }
}
