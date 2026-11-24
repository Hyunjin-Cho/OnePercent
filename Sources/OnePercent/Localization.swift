import Foundation

/// Localized text. OnePercent ships the same 29 languages as PomoLight, written from the Korean originals.
///
/// The language follows **your app's** language (`Bundle.main.preferredLocalizations`), matched against the
/// languages OnePercent has, so the update text never appears in a different language from the rest of your app.
/// English is the fallback.
enum L10n {
    struct Table: Sendable {
        let language: String
        let bundle: Bundle?

        /// The format for `key` with `arguments` filled in (`%@` and positional `%1$@`). Missing keys fall back to English —
        /// the bundle's, or the copy built into the code when there is no bundle (#34).
        func text(_ key: String, _ arguments: String...) -> String {
            // 2026-11-24 (#49): 자리표시가 넘기는 값보다 많거나 `%@` 가 아닌 문장은 쓰지 않는다 — `String(format:)` 이 없는 값을 읽어 앱이 꺼진다.
            func usable(_ format: String?) -> String? {
                guard let format, format != key, L10n.fits(format, arguments: arguments.count) else { return nil }
                return format
            }
            let format = usable(bundle?.localizedString(forKey: key, value: nil, table: nil))
                ?? usable(L10n.english.bundle?.localizedString(forKey: key, value: nil, table: nil))
                ?? usable(EmbeddedEnglish.strings[key])
                ?? key
            guard !arguments.isEmpty else { return format }
            return String(format: format, locale: Locale(identifier: language), arguments: arguments.map { $0 as NSString })
        }

        /// A byte count, for example "200 MB" (formatted by the system's own locale — `ByteCountFormatter` has no locale setting).
        func bytes(_ count: Int) -> String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(count))
        }

        /// A fraction as a percentage in the table's language, for example "42%".
        func percent(_ fraction: Double) -> String {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: language)
            formatter.numberStyle = .percent
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: min(max(fraction, 0), 1))) ?? "\(Int(fraction * 100))%"
        }

        /// A date without the time, long style, in the table's language and the user's region.
        func date(_ date: Date) -> String {
            let region = Locale.current.region?.identifier
            let identifier = language.contains("-") || region == nil ? language : "\(language)_\(region!)"
            return date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(Locale(identifier: identifier)))
        }
    }

    /// Languages OnePercent has strings for (the `.lproj` folders in its resource bundle). Only English without the bundle.
    static var available: [String] { resources?.localizations.filter { $0 != "Base" } ?? ["en"] }

    /// The raw table of one language, for consistency tests.
    static func rawStrings(_ language: String) -> [String: String]? {
        resources?.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] }
    }

    /// The table for one language code such as `ko` or `pt-BR`. Unknown codes fall back to English.
    static func table(_ language: String) -> Table {
        let matched = Bundle.preferredLocalizations(from: available, forPreferences: [language]).first ?? "en"
        let path = resources?.path(forResource: matched, ofType: "lproj")
        return Table(language: matched, bundle: path.flatMap(Bundle.init(path:)))
    }

    static let english: Table = {
        let path = resources?.path(forResource: "en", ofType: "lproj")
        return Table(language: "en", bundle: path.flatMap(Bundle.init(path:)))
    }()

    /// OnePercent's resource bundle, or `nil` when it is nowhere to be found (then the text is the built-in English).
    ///
    /// 2026-11-24 (#34): `Bundle.module` 을 쓰지 않는다. SwiftPM 의 예전 빌드 시스템(native)이 만드는 접근자는 `.app` 안 맨 위와
    /// 개발자 Mac 의 빌드 경로만 보고 없으면 `fatalError` 다 — README 대로 `Contents/Resources` 에 넣어 손으로 조립한 앱이
    /// 개발자 Mac 에선 돌고(빌드 경로) 사용자 Mac 에선 문구를 처음 쓰는 순간 꺼졌다. Swift Build 의 접근자도 못 찾으면 `fatalError`.
    /// 두 접근자가 보는 자리를 모두 직접 보고, 없으면 끄는 대신 영어로 간다.
    static let resources: Bundle? = ResourceBundle.locate(in: ResourceBundle.candidates())

    /// The table matching the app's own language (fixed for the life of the process, like the app's own language).
    static let current: Table = table(Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en")

    /// `format` uses only `%@` (plain or positional `%2$@`) and `%%`, and no position beyond `count` arguments.
    static func fits(_ format: String, arguments count: Int) -> Bool {
        let characters = Array(format)
        var index = 0, next = 1
        while index < characters.count {
            guard characters[index] == "%" else { index += 1; continue }
            index += 1
            guard index < characters.count else { return false }
            if characters[index] == "%" { index += 1; continue }
            var digits = ""
            while index < characters.count, characters[index].isASCII, characters[index].isNumber { digits.append(characters[index]); index += 1 }
            var position = next
            if !digits.isEmpty {
                guard index < characters.count, characters[index] == "$", let number = Int(digits), number > 0 else { return false }
                position = number
                index += 1
            } else {
                next += 1
            }
            guard index < characters.count, characters[index] == "@", position <= count else { return false }
            index += 1
        }
        return true
    }

    /// Korean picks 로/으로 by the sound of the last character: a final consonant other than ㄹ takes 으로.
    /// Digits are read as Sino-Korean numbers — 0(영)·3(삼)·6(육) end in a consonant; 1(일)·7(칠)·8(팔) end in ㄹ and take 로.
    /// 2026-11-18 (하늘키보드 #273) 규칙을 숫자 아닌 끝 글자(한글·영문)까지 넓혔다. 영문 등 모르는 끝은 "(으)로".
    static func koreanDirectionalParticle(after text: String) -> String {
        guard let last = text.last else { return "(으)로" }
        if last.isASCII, last.isNumber { return "036".contains(last) ? "으로" : "로" }
        if let scalar = last.unicodeScalars.first, last.unicodeScalars.count == 1,
           (0xAC00...0xD7A3).contains(scalar.value) {
            let final = (scalar.value - 0xAC00) % 28
            return final == 0 || final == 8 ? "로" : "으로"   // 8 = ㄹ
        }
        return "(으)로"
    }
}

/// Ready-made, localized text for building your own update UI. Every value follows your app's language.
public enum OnePercentText {
    public static var installedVersion: String { L10n.current.text("ui.installedVersion") }
    public static var latestVersion: String { L10n.current.text("ui.latestVersion") }
    /// Shown as the latest version before the first check.
    public static var notCheckedYet: String { L10n.current.text("ui.notCheckedYet") }
    public static var checkNow: String { L10n.current.text("ui.checkNow") }
    public static var neverChecked: String { L10n.current.text("ui.neverChecked") }
    /// "Last checked: <date>" — the date without the time.
    public static func lastChecked(_ date: Date) -> String {
        let table = L10n.current
        return table.text("ui.lastChecked", table.date(date))
    }
    /// The label for the switch that turns background checks on and off.
    public static var automaticChecks: String { L10n.current.text("ui.automaticChecks") }
    public static var install: String { L10n.current.text("ui.install") }
    public static var cancel: String { L10n.current.text("ui.cancel") }
    public static var releaseNotes: String { L10n.current.text("ui.releaseNotes") }
    public static var later: String { L10n.current.text("ui.later") }
    public static var checking: String { L10n.current.text("status.checking") }
    public static var upToDate: String { L10n.current.text("status.upToDate") }
    public static var available: String { L10n.current.text("status.available") }
    /// "Downloading…" or, with a known fraction, "Downloading… 42%".
    public static func downloading(_ fraction: Double?) -> String {
        let table = L10n.current
        guard let fraction else { return table.text("status.downloading") }
        return table.text("status.downloadingProgress", table.percent(fraction))
    }
    public static var verifying: String { L10n.current.text("status.verifying") }
    public static var installing: String { L10n.current.text("status.installing") }
    /// "Updated to <version>." — for the first launch after an update.
    public static func updated(to version: String) -> String { updated(to: version, table: L10n.current) }
    static func updated(to version: String, table: L10n.Table) -> String {
        table.text("status.updated", version, table.language == "ko" ? L10n.koreanDirectionalParticle(after: version) : "")
    }
    /// "Update error: <reason> (<code>)" — the code is ``OnePercentError/diagnosticCode``, so a screenshot in any language
    /// can be read. Your app's own refusal (``OnePercentError/blocked(_:)``) and a cancel carry no code.
    public static func error(_ error: OnePercentError) -> String { self.error(error, table: L10n.current) }
    static func error(_ error: OnePercentError, table: L10n.Table) -> String {
        let text = table.text("status.error", error.message(table))
        switch error {
        case .blocked, .cancelled: return text
        default: return "\(text) (\(error.diagnosticCode))"
        }
    }
    /// The heading of a "new version" notice, with your app's name.
    public static func noticeTitle(appName: String) -> String { L10n.current.text("notice.title", appName) }
    public static var noticeCurrentVersion: String { L10n.current.text("notice.current") }
    public static var noticeNewVersion: String { L10n.current.text("notice.new") }
    public static var noticeBody: String { L10n.current.text("notice.body") }
    public static var noticeShow: String { L10n.current.text("notice.show") }
}

/// Where OnePercent's resource bundle (`OnePercent_OnePercent.bundle`) can be.
enum ResourceBundle {
    static let name = "OnePercent_OnePercent.bundle"

    private final class Finder {}

    /// Folders that may hold the bundle, in order: the app's `Contents/Resources` (Xcode, Swift Build, a hand-assembled app),
    /// the app's top folder `<App>.app/` or a tool's folder (SwiftPM's native build system), the executable's folder — all
    /// inside the app — and, only when OnePercent is not the main bundle (a framework, a test bundle), that bundle's resources
    /// and the folder it sits in.
    /// 2026-11-24 (#49, 0.2.0 리뷰 P2): 0.2.0 은 OnePercent 가 앱에 함께 빌드됐을 때도 "자기 번들의 부모 폴더"를 봤다 — 그건 `.app` 이
    /// 들어 있는 `/Applications` 같은 **앱 바깥**이다. 관리자 그룹 프로그램이 거기 둔 묶음의 문구가 화면에 나왔고, 자리표시를 더 넣은
    /// 문구는 앱을 끄게 했다(리뷰어 재현). 앱 바깥은 테스트 묶음·프레임워크일 때만 본다.
    static func candidates() -> [URL] {
        candidates(main: Bundle.main, own: Bundle(for: Finder.self), environment: ProcessInfo.processInfo.environment)
    }

    static func candidates(main: Bundle, own: Bundle, environment: [String: String]) -> [URL] {
        var folders: [URL?] = []
        #if DEBUG
        // Swift Build's own accessor honours these while testing (`swift test`).
        if let override = environment["PACKAGE_RESOURCE_BUNDLE_PATH"] ?? environment["PACKAGE_RESOURCE_BUNDLE_URL"] {
            folders.append(URL(fileURLWithPath: override))
        }
        #endif
        folders += [
            main.resourceURL,
            main.bundleURL,
            main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent(),
        ]
        if own.bundleURL.standardizedFileURL != main.bundleURL.standardizedFileURL {
            folders += [own.resourceURL, own.bundleURL.deletingLastPathComponent()]
        }
        var seen: Set<String> = []
        return folders.compactMap { $0?.standardizedFileURL }.filter { seen.insert($0.path).inserted }
    }

    /// The first folder's bundle that really holds OnePercent's English strings. A folder that is the bundle itself
    /// (the testing override) counts too.
    static func locate(in folders: [URL]) -> Bundle? {
        for folder in folders {
            let url = folder.lastPathComponent == name ? folder : folder.appendingPathComponent(name)
            if let bundle = Bundle(url: url),
               bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en") != nil {
                return bundle
            }
        }
        return nil
    }
}
