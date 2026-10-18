import Foundation

/// In-app localization, independent of the macOS language (`ui.language` in config.json).
/// Keys are the English texts; `L10nTable.table` holds the other languages.
public enum L {
    public enum Language: String, CaseIterable, Codable, Sendable {
        case en, it, fr, es, pt, de, zh, ja, ru

        /// Name shown in the language picker, in the language itself.
        public var nativeName: String {
            switch self {
            case .en: return "English"
            case .it: return "Italiano"
            case .fr: return "Français"
            case .es: return "Español"
            case .pt: return "Português"
            case .de: return "Deutsch"
            case .zh: return "中文（简体）"
            case .ja: return "日本語"
            case .ru: return "Русский"
            }
        }
    }

    nonisolated(unsafe) public static var language: Language = .en

    /// Translation of an English text; falls back to English when missing.
    public static func t(_ english: String) -> String {
        guard language != .en else { return english }
        return L10nTable.table[english]?[language.rawValue] ?? english
    }

    /// Translated format string (`%@`, `%d`, `%.1f` …) with arguments.
    public static func f(_ english: String, _ args: CVarArg...) -> String {
        String(format: t(english), arguments: args)
    }
}
