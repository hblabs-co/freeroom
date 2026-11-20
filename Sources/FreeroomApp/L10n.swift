import Foundation

/// In-app language (chosen in Settings, independent from the system language).
/// Translations live in localization/strings.json and are embedded by scripts/gen-l10n.py.
enum L10n {
    struct Language: Identifiable, Hashable {
        let id: String      // BCP-47 code, also used for /freeroom:translate
        let name: String    // endonym
    }

    static let languages: [Language] = [
        .init(id: "en", name: "English"),
        .init(id: "es", name: "Español"),
        .init(id: "de", name: "Deutsch"),
        .init(id: "fr", name: "Français"),
        .init(id: "it", name: "Italiano"),
        .init(id: "pt", name: "Português"),
        .init(id: "nl", name: "Nederlands"),
        .init(id: "pl", name: "Polski"),
        .init(id: "ru", name: "Русский"),
        .init(id: "ja", name: "日本語"),
        .init(id: "zh-Hans", name: "简体中文"),
        .init(id: "zh-Hant", name: "繁體中文（台灣）"),
        .init(id: "ko", name: "한국어"),
        .init(id: "hi", name: "हिन्दी"),
        .init(id: "id", name: "Bahasa Indonesia"),
        .init(id: "vi", name: "Tiếng Việt"),
    ]

    nonisolated(unsafe) static var current = "en"

    static var preferredSystemLanguage: String {
        for preferred in Locale.preferredLanguages {
            if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") { return "zh-Hant" }
            if preferred.hasPrefix("zh") { return "zh-Hans" }
            let base = String(preferred.prefix(2))
            if languages.contains(where: { $0.id == base }) { return base }
        }
        return "en"
    }

    /// Translated string for an English key; falls back to the key itself.
    static func string(_ key: String) -> String {
        guard current != "en" else { return key }
        return L10nData.table[key]?[current] ?? key
    }
}

/// Shorthand used in views: `L("Free space")`.
func L(_ key: String) -> String { L10n.string(key) }
