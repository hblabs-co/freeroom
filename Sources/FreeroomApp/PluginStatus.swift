import Foundation
import FreeroomCore

/// Which Claude Code plugin version is published, installed and actually used, and whether an
/// update is available. Published = plugin.json on GitHub (checked at most once a day, no user data
/// sent); installed = Claude Code's plugin registry; used = recorded by the CLI with each agent scan.
struct PluginStatus: Equatable {
    var installed: String?
    var installedAt: Date?
    var published: String?
    var lastUsed: String?
    var checkedAt: Date?

    var updateAvailable: Bool {
        guard let published, let current = installed ?? lastUsed else { return false }
        return Self.compare(current, published) == .orderedAscending
    }

    static let pluginId = "freeroom@freeroom"
    static let updateCommand = "claude plugin update freeroom@freeroom"
    static let publishedURL = URL(string: "https://raw.githubusercontent.com/hblabs-co/freeroom/main/plugin/.claude-plugin/plugin.json")!

    /// Reads Claude Code's registry (~/.claude/plugins/installed_plugins.json) defensively:
    /// it is Claude Code's internal file, so any format change just yields "unknown".
    static func readInstalled() -> (version: String?, at: Date?) {
        let url = URL(fileURLWithPath: PathUtils.expand("~/.claude/plugins/installed_plugins.json"))
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = root["plugins"] as? [String: Any],
              let entries = plugins[pluginId] as? [[String: Any]],
              let entry = entries.first(where: { ($0["scope"] as? String) == "user" }) ?? entries.first
        else { return (nil, nil) }
        let date = (entry["lastUpdated"] as? String).flatMap { ISO8601DateFormatter.withFractions.date(from: $0) }
        return (entry["version"] as? String, date)
    }

    static func fetchPublished() async -> String? {
        var request = URLRequest(url: publishedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("Freeroom/\(Freeroom.version)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["version"] as? String
    }

    /// Numeric semver comparison ("0.10.0" > "0.9.1").
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

import SwiftUI

/// "Plugin update available" notice with the exact command and a Copy button.
struct PluginUpdateBanner: View {
    let status: PluginStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent).font(.fr(.title3))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Plugin update available")).font(.fr(.callout).weight(.semibold))
                    Text("\(status.installed ?? status.lastUsed ?? "?") → \(status.published ?? "?")")
                        .font(.fr(.caption)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            CopyField(text: PluginStatus.updateCommand)
            Text(L("Run it in Terminal, then restart Claude Code.")).font(.fr(.caption)).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent.opacity(0.5)))
    }
}

/// Published / installed / last-used versions, for Settings › Claude Code.
struct PluginVersionCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.plugin
        VStack(alignment: .leading, spacing: 8) {
            versionRow("shippingbox", L("Installed"), s.installed ?? L("Not installed"),
                       detail: s.installedAt.map { $0.formatted(date: .abbreviated, time: .omitted) })
            versionRow("clock", L("Used in last scan"), s.lastUsed ?? "—", detail: nil)
            versionRow("globe", L("Latest published"), s.published ?? "—",
                       detail: s.checkedAt.map { String(format: L("checked %@"), $0.formatted(.relative(presentation: .named))) })
            if s.updateAvailable {
                PluginUpdateBanner(status: s)
            } else if s.installed != nil, s.published != nil {
                Label(L("Plugin is up to date"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            }
        }
    }

    private func versionRow(_ symbol: String, _ title: String, _ value: String, detail: String?) -> some View {
        HStack(spacing: 10) {
            RowIcon(symbol: symbol)
            Text(title)
            Spacer()
            if let detail { Text(detail).font(.fr(.caption)).foregroundStyle(.secondary) }
            Text(value).font(.fr(.body, design: .monospaced))
        }
    }
}
