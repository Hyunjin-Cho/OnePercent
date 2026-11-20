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

        /// The format for `key` with `arguments` filled in (`%@` and positional `%1$@`). Missing keys fall back to English.
        func text(_ key: String, _ arguments: String...) -> String {
            var format = bundle?.localizedString(forKey: key, value: nil, table: nil) ?? key
            if format == key, language != "en" {
                format = L10n.english.bundle?.localizedString(forKey: key, value: nil, table: nil) ?? key
            }
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

    /// Languages OnePercent has strings for (the `.lproj` folders in its resource bundle).
    static var available: [String] { Bundle.module.localizations.filter { $0 != "Base" } }

    /// The raw table of one language, for consistency tests.
    static func rawStrings(_ language: String) -> [String: String]? {
        Bundle.module.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] }
    }

    /// The table for one language code such as `ko` or `pt-BR`. Unknown codes fall back to English.
    static func table(_ language: String) -> Table {
        let matched = Bundle.preferredLocalizations(from: available, forPreferences: [language]).first ?? "en"
        let path = Bundle.module.path(forResource: matched, ofType: "lproj")
        return Table(language: matched, bundle: path.flatMap(Bundle.init(path:)))
    }

    static let english: Table = {
        let path = Bundle.module.path(forResource: "en", ofType: "lproj")
        return Table(language: "en", bundle: path.flatMap(Bundle.init(path:)))
    }()

    /// The table matching the app's own language (fixed for the life of the process, like the app's own language).
    static let current: Table = table(Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en")

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
    /// "Update error: <reason>".
    public static func error(_ error: OnePercentError) -> String {
        let table = L10n.current
        return table.text("status.error", error.message(table))
    }
    /// The heading of a "new version" notice, with your app's name.
    public static func noticeTitle(appName: String) -> String { L10n.current.text("notice.title", appName) }
    public static var noticeCurrentVersion: String { L10n.current.text("notice.current") }
    public static var noticeNewVersion: String { L10n.current.text("notice.new") }
    public static var noticeBody: String { L10n.current.text("notice.body") }
    public static var noticeShow: String { L10n.current.text("notice.show") }
}
