import Foundation
import Testing
@testable import FXMicCore

@Suite(.serialized) struct L10nTests {
    @Test func englishIsTheDefaultAndKeysAreEnglish() {
        #expect(AppConfig().ui.language == .en)
        L.language = .en
        #expect(L.t("Settings…") == "Settings…")
    }

    @Test func everyRowHasAllLanguagesAndSameFormatSpecifiers() {
        let spec = try! NSRegularExpression(pattern: "%(?:\\.\\d+)?[@dfs]")
        func specs(_ s: String) -> [String] {
            spec.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }
        }
        for (key, values) in L10nTable.table {
            #expect(Set(values.keys) == Set(L.Language.allCases.filter { $0 != .en }.map(\.rawValue)), "\(key)")
            for value in values.values { #expect(specs(value) == specs(key), "\(key) -> \(value)") }
        }
    }

    @Test func translatesAndFormatsThenFallsBack() {
        L.language = .it
        #expect(L.t("Quit") == "Esci")
        #expect(L.f("%d profiles", 3) == "3 profili")
        #expect(L.f("Profile in use: %@", "Claude") == "Profilo in uso: Claude")
        L.language = .ja
        #expect(L.t("Settings…") == "設定…")
        #expect(L.t("Not a key") == "Not a key")
        L.language = .en
    }

    @Test func languageDecodesFromConfig() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"ui":{"language":"de"}}"#.utf8))
        #expect(config.ui.language == .de)
        let bad = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"ui":{"language":"xx"}}"#.utf8))
        #expect(bad.ui.language == .en)
    }
}
