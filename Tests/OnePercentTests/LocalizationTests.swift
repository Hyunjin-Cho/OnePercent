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

    /// 2026-11-22 (#10): 대소문자는 보지 않는다. SwiftPM 의 예전 빌드 시스템(Swift 6.3 이하 — CI 의 Xcode 26.6)은 `.lproj` 이름을
    /// 소문자로 담고(`pt-br.lproj`), Swift Build(Swift 6.4 기본)와 Xcode 앱 빌드(PomoLight)는 그대로 둔다(`pt-BR.lproj`).
    /// 어느 쪽이든 고르는 언어는 같았다(CI: `pt-BR` → `pt-br`, `fr-CA` → `fr`).
    @Test func sameLanguagesAsPomoLight() {
        #expect(Set(L10n.available.map { $0.lowercased() }) == Set(Self.languages.map { $0.lowercased() }), "\(L10n.available.sorted())")
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

    /// Case is not compared — see ``sameLanguagesAsPomoLight()``.
    @Test func languageMatching() {
        func matched(_ code: String) -> String { L10n.table(code).language.lowercased() }
        #expect(matched("ko") == "ko")
        #expect(matched("ko-KR") == "ko")
        #expect(matched("pt-BR") == "pt-br")
        #expect(matched("pt-PT") == "pt-pt")
        #expect(matched("zh-Hant-TW") == "zh-hant")
        #expect(matched("zh-Hans-CN") == "zh-hans")
        #expect(matched("fr-CA") == "fr")
        #expect(matched("xx") == "en", "unknown languages fall back to English")
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

    // MARK: - Codes shown with errors (#35)

    /// 2026-11-24 (#35): 어느 언어 화면 캡처든 오류를 알아볼 수 있게, 보여 주는 문장 끝에 코드를 붙인다.
    @Test func shownErrorsCarryTheirCode() {
        let ko = L10n.table("ko")
        #expect(OnePercentText.error(.rateLimited, table: ko).hasSuffix(" (rateLimited)"))
        let failed = OnePercentError.verificationFailed([.notSignedByTeam, .notarizationRejected])
        #expect(failed.diagnosticCode == "verificationFailed: notSignedByTeam, notarizationRejected")
        #expect(OnePercentText.error(failed, table: L10n.table("th")).hasSuffix("(verificationFailed: notSignedByTeam, notarizationRejected)"))
        #expect(OnePercentError.archiveRejected(.outsideApp(appFolder: "A.app")).diagnosticCode == "archiveRejected: outsideApp")
        #expect(OnePercentError.httpStatus(503).diagnosticCode == "httpStatus: 503")
        #expect(OnePercentError.busy.diagnosticCode == "busy")
        #expect(OnePercentText.error(.blocked("A timer is running."), table: L10n.table("en")) == "Update error: A timer is running.",
                "the app's own reason carries no code")
        #expect(OnePercentText.error(.cancelled, table: ko) == ko.text("status.error", OnePercentError.cancelled.message(ko)))
        #expect(OnePercentError.rateLimited.message(ko) == ko.text("error.rateLimited"), "the message itself stays plain")
    }

    @Test func detailCodesAreDistinct() {
        let failures: [VerificationFailure] = [.bundleIdentifierMismatch, .notSignedByTeam, .codeSignatureInvalid, .notarizationRejected,
                                               .versionNotHigher, .buildNotHigher, .buildUnreadable,
                                               .releaseMismatch(bundleVersion: nil, releaseVersion: "1"), .versionUnreadable,
                                               .notARealFolder, .copyChanged]
        let problems: [ArchiveProblem] = [.unreadableListing, .empty, .tooManyEntries(count: 1, max: 1), .tooLarge(maxMB: 1),
                                          .outsideApp(appFolder: "A"), .linkedEntry(appFolder: "A"), .unexpectedTopLevel(appFolder: "A", count: 1),
                                          .extractedTooLarge(maxMB: 1), .extractedTooManyItems(max: 1), .extractionTimedOut(seconds: 1),
                                          .escapingLink(appFolder: "A"), .missingApp(appFolder: "A")]
        #expect(Set(failures.map(\.code)).count == failures.count)
        #expect(Set(problems.map(\.code)).count == problems.count)
    }

    // MARK: - Resource bundle (#34)

    /// 2026-11-24 (#34): `Bundle.module` 의 접근자는 묶음을 못 찾으면 앱을 끈다(native 빌드: `.app` 바로 옆과 개발 Mac 빌드 경로만 봄).
    /// 소스 어디에서도 부르지 않는다 — 부르는 순간 그 앱은 묶음 자리가 맞지 않는 사용자 Mac 에서 꺼질 수 있다.
    @Test func neverTouchesBundleModule() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OnePercent")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        #expect(files.count > 10, "\(sources.path)")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            #expect(!code.contains { $0.contains("Bundle.module") }, "\(file.lastPathComponent)")
        }
    }

    @Test func theBundleIsFoundWhileTesting() {
        #expect(L10n.resources != nil, "candidates: \(ResourceBundle.candidates().map(\.path))")
    }

    @Test func theBuiltInEnglishIsTheEnglishFile() throws {
        let english = try #require(L10n.rawStrings("en"))
        #expect(EmbeddedEnglish.strings == english, "run scripts/embed-english.sh")
    }

    /// The places SwiftPM's two build systems and Xcode put the bundle: `Contents/Resources`, next to the app, next to a tool.
    @Test func bundleIsFoundWhereBuildsPutIt() throws {
        let root = try Fixture.temporaryRoot("bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        func makeBundle(in folder: URL, nested: Bool) throws {
            let base = folder.appendingPathComponent(ResourceBundle.name)
            let strings = (nested ? base.appendingPathComponent("Contents/Resources") : base).appendingPathComponent("en.lproj")
            try FileManager.default.createDirectory(at: strings, withIntermediateDirectories: true)
            try Data("\"ui.checkNow\" = \"Check Now\";".utf8).write(to: strings.appendingPathComponent("Localizable.strings"))
        }
        let app = root.appendingPathComponent("Hand.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(ResourceBundle.locate(in: [empty, app, resources]) == nil, "nowhere yet")

        try makeBundle(in: resources, nested: false)
        #expect(ResourceBundle.locate(in: [empty, app, resources])?.bundleURL.standardizedFileURL.path
                == resources.appendingPathComponent(ResourceBundle.name).standardizedFileURL.path, "Contents/Resources (README, Xcode)")

        let native = root.appendingPathComponent("Native.app")
        try FileManager.default.createDirectory(at: native, withIntermediateDirectories: true)
        try makeBundle(in: native, nested: true)
        #expect(ResourceBundle.locate(in: [empty, native]) != nil, "next to the app (SwiftPM native)")
        #expect(ResourceBundle.locate(in: [native.appendingPathComponent(ResourceBundle.name)]) != nil, "the override names the bundle itself")

        let hollow = root.appendingPathComponent("Hollow")
        try FileManager.default.createDirectory(at: hollow.appendingPathComponent(ResourceBundle.name), withIntermediateDirectories: true)
        #expect(ResourceBundle.locate(in: [hollow]) == nil, "a folder with that name but no English strings is not it")
    }

    /// 2026-11-24 (#49): with OnePercent built into the app, every place looked at is inside the app — never the folder the
    /// app sits in. Only a separate bundle (test bundle, framework) adds its own folder.
    @Test func neverLooksOutsideTheApp() throws {
        let root = try Fixture.temporaryRoot("candidates")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try Fixture.makeApp(root.appendingPathComponent("Applications/Hand.app"), version: "1.0", build: "1",
                                      extraInfo: ["CFBundleExecutable": Fixture.appName])
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        let outside = app.deletingLastPathComponent().standardizedFileURL.path
        let main = try #require(Bundle(url: app))
        let inApp = ResourceBundle.candidates(main: main, own: main, environment: [:]).map(\.path)
        #expect(!inApp.isEmpty && inApp.allSatisfy { $0.hasPrefix(app.standardizedFileURL.path) }, "\(inApp)")
        #expect(!inApp.contains(outside))
        #expect(inApp.contains(app.appendingPathComponent("Contents/Resources").standardizedFileURL.path), "Contents/Resources")
        #expect(inApp.contains(app.standardizedFileURL.path), "the app's top folder (SwiftPM native)")

        let tests = root.appendingPathComponent("build/Tests.xctest")
        try FileManager.default.createDirectory(at: tests.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let own = try #require(Bundle(url: tests))
        let separate = ResourceBundle.candidates(main: main, own: own, environment: [:]).map(\.path)
        #expect(separate.contains(root.appendingPathComponent("build").standardizedFileURL.path), "next to a test bundle: \(separate)")
        #expect(!separate.contains(outside))
    }

    /// A format that asks for more values than are passed, or for anything but `%@`, is never used — English instead.
    @Test func unsafeFormatsAreNotUsed() throws {
        #expect(L10n.fits("Server error (HTTP %@).", arguments: 1))
        #expect(L10n.fits("%1$@ needs %2$@ (%3$@) 100%%", arguments: 3))
        #expect(L10n.fits("%2$@ %1$@", arguments: 2))
        for bad in ["%@ %@", "%2$@", "%d", "%s", "%n", "%", "%0$@", "%1$d", "100%"] {
            #expect(!L10n.fits(bad, arguments: 1), "\(bad)")
        }
        let root = try Fixture.temporaryRoot("planted")
        defer { try? FileManager.default.removeItem(at: root) }
        let lproj = root.appendingPathComponent("xx.lproj")
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        try Data("\"error.httpStatus\" = \"%@ %@ %@ %@ %@ %@\";\n\"ui.checkNow\" = \"%d\";\n\"ui.cancel\" = \"Annuler\";".utf8)
            .write(to: lproj.appendingPathComponent("Localizable.strings"))
        let planted = L10n.Table(language: "xx", bundle: Bundle(url: lproj))
        #expect(planted.text("error.httpStatus", "500") == "Server error (HTTP 500).", "no crash, English")
        #expect(planted.text("ui.checkNow") == "Check Now")
        #expect(planted.text("ui.cancel") == "Annuler", "a harmless string is still used")
    }

    /// Without a bundle the text is English from the code — never the key, never a crash.
    @Test func withoutABundleTheTextIsEnglish() {
        let table = L10n.Table(language: "en", bundle: nil)
        #expect(table.text("ui.checkNow") == "Check Now")
        #expect(table.text("status.error", "x") == "Update error: x")
        #expect(OnePercentError.rateLimited.message(table) == EmbeddedEnglish.strings["error.rateLimited"])
        #expect(table.text("no.such.key") == "no.such.key")
    }

    @Test func updatedLine() {
        #expect(OnePercentText.updated(to: "1.0", table: L10n.table("ko")) == "1.0으로 업데이트했어요.")
        #expect(OnePercentText.updated(to: "2026.11.17", table: L10n.table("ko")) == "2026.11.17로 업데이트했어요.")
        #expect(OnePercentText.updated(to: "1.1", table: L10n.table("en")) == "Updated to 1.1.")
        #expect(OnePercentText.updated(to: "1.1", table: L10n.table("ja")) == "1.1 にアップデートしました。")
    }
}
