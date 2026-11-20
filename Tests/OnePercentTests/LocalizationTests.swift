import Foundation
import Testing
@testable import OnePercent

/// 2026-11-20: 29개 언어(PomoLight 와 같은 목록)가 같은 키·같은 자리표시를 갖는지 본다. 문장 자체의 질은 사람이 본다.
@Suite struct LocalizationTests {
    static let languages = ["cs", "da", "de", "el", "en", "es", "fi", "fil", "fr", "hu", "id", "it", "ja", "ko", "ms", "nb", "nl",
                            "pl", "pt-BR", "pt-PT", "ro", "ru", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant"]

    /// Positions used by a format: `%@` counts in order, `%2$@` is position 2.
    static func positions(_ format: String) -> Set<Int> {
        var result: Set<Int> = []
        var next = 1
        let regex = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?@")
        for match in regex.matches(in: format, range: NSRange(format.startIndex..., in: format)) {
            if let range = Range(match.range(at: 1), in: format), let n = Int(format[range]) { result.insert(n) }
            else { result.insert(next); next += 1 }
        }
        return result
    }

    @Test func sameLanguagesAsPomoLight() {
        #expect(Set(L10n.available) == Set(Self.languages), "\(L10n.available.sorted())")
    }

    @Test(arguments: languages) func sameKeysAndPlaceholders(_ language: String) throws {
        let english = try #require(L10n.rawStrings("en"))
        let table = try #require(L10n.rawStrings(language), "\(language) is missing")
        #expect(Set(table.keys) == Set(english.keys), "\(language): extra \(Set(table.keys).subtracting(english.keys)), missing \(Set(english.keys).subtracting(table.keys))")
        for (key, value) in table {
            #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty || key == "list.separator", "\(language) \(key) is empty")
            guard let source = english[key] else { continue }
            let expected = key == "status.updated" && language == "ko" ? Set([1, 2]) : Self.positions(source)
            #expect(Self.positions(value) == expected, "\(language) \(key): \(value)")
            #expect(!value.contains("%d") && !value.contains("%s"), "\(language) \(key): only %@ placeholders")
        }
    }

    @Test func languageMatching() {
        #expect(L10n.table("ko").language == "ko")
        #expect(L10n.table("ko-KR").language == "ko")
        #expect(L10n.table("pt-BR").language == "pt-BR")
        #expect(L10n.table("pt-PT").language == "pt-PT")
        #expect(L10n.table("zh-Hant-TW").language == "zh-Hant")
        #expect(L10n.table("zh-Hans-CN").language == "zh-Hans")
        #expect(L10n.table("fr-CA").language == "fr")
        #expect(L10n.table("xx").language == "en", "unknown languages fall back to English")
    }

    @Test(arguments: languages) func everyErrorRenders(_ language: String) {
        let table = L10n.table(language)
        let errors: [OnePercentError] = [
            .badConfiguration("x"), .network("x"), .httpStatus(500), .rateLimited, .noRelease("o/r"), .redirectBlocked("u"),
            .malformedResponse, .responseTooLarge(1024), .assetNotReady("1.1"), .badSize(10), .sizeMismatch(expected: 1, actual: 2),
            .digestMismatch, .extractFailed("x"), .translocated, .readOnlyVolume, .busy, .blocked("App reason"), .cancelled,
            .replaceFailed("x"), .stagingUnsafe, .copyChanged, .placeFailedRestored, .relaunchFailed("x"),
            .notAtRequiredLocation(required: "/Applications/A.app", running: "/tmp/A.app"),
            .replaceRecoveryFailed(reason: "r", backupPath: "/b", destinationPath: "/d"),
            .verificationFailed([.bundleIdentifierMismatch, .notSignedByTeam, .codeSignatureInvalid, .notarizationRejected, .versionNotHigher,
                                 .releaseMismatch(bundleVersion: nil, releaseVersion: "1.1"), .versionUnreadable, .notARealFolder, .copyChanged]),
        ] + [ArchiveProblem.unreadableListing, .empty, .tooManyEntries(count: 3, max: 2), .tooLarge(maxMB: 512), .outsideApp(appFolder: "A.app"),
             .linkedEntry(appFolder: "A.app"), .unexpectedTopLevel(appFolder: "A.app", count: 2), .extractedTooLarge(maxMB: 512),
             .extractedTooManyItems(max: 2000), .extractionTimedOut(seconds: 120), .escapingLink(appFolder: "A.app"),
             .missingApp(appFolder: "A.app")].map(OnePercentError.archiveRejected)
        for error in errors {
            let text = error.message(table)
            #expect(!text.isEmpty && !text.contains("%") && !text.contains("error.") && !text.contains("archive.") && !text.contains("verify."),
                    "\(language) \(error.code): \(text)")
        }
    }

    @Test func updatedLine() {
        #expect(OnePercentText.updated(to: "1.0", table: L10n.table("ko")) == "1.0으로 업데이트했어요.")
        #expect(OnePercentText.updated(to: "2026.11.17", table: L10n.table("ko")) == "2026.11.17로 업데이트했어요.")
        #expect(OnePercentText.updated(to: "1.1", table: L10n.table("en")) == "Updated to 1.1.")
        #expect(OnePercentText.updated(to: "1.1", table: L10n.table("ja")) == "1.1 にアップデートしました。")
    }
}
