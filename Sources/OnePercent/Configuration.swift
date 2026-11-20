import Foundation

/// Everything OnePercent needs to know about your app and where its releases live.
///
/// ```swift
/// let configuration = OnePercentConfiguration(
///     repository: "you/YourApp",
///     teamIdentifier: "ABCDE12345",
///     bundleIdentifier: "com.example.yourapp",
///     appName: "YourApp")
/// ```
///
/// Only those four are required. The release ZIP must be named `YourApp_<tag>.zip` by default and contain
/// `YourApp.app` at its top level (`ditto -c -k --keepParent YourApp.app YourApp_<tag>.zip`).
public struct OnePercentConfiguration: Sendable {
    /// GitHub `owner/name` whose **latest** release is checked. Drafts and pre-releases are ignored.
    public var repository: String
    /// The 10-character Apple Team ID that signs your Developer ID builds. A download signed by anyone else is refused.
    public var teamIdentifier: String
    /// The bundle identifier the downloaded app must have.
    public var bundleIdentifier: String
    /// Your app's name without `.app`. The release ZIP must contain exactly `<appName>.app` at its top level.
    public var appName: String

    /// How versions are read and ordered. Default: ``VersionScheme/numeric`` (`1.0`, `1.2.3`, `2026.11.17`).
    public var versionScheme: VersionScheme
    /// Text in front of the version in your release tags, such as `"v"` for `v1.2.0`. Default: none.
    public var tagPrefix: String
    /// The release asset file name for a tag. `nil` (default) means `<appName>_<tag>.zip`.
    public var assetName: (@Sendable (_ tag: String) -> String)?
    /// An optional Info.plist key whose string value is appended to `CFBundleShortVersionString` to form the
    /// public version (for example `_hotfix1`). Info.plist is covered by the code signature, so the value can be trusted.
    public var versionSuffixInfoKey: String?
    /// Also require `CFBundleVersion` (the build number) to increase. Default: `true`.
    public var requireBuildIncrease: Bool

    /// How often the background check runs. Default: ``CheckSchedule/monthly``.
    public var schedule: CheckSchedule
    /// Whether background checks are on before the user ever touches the switch. Default: `true`.
    /// Background checks only *tell* the user — installing always needs a button press.
    public var automaticChecksByDefault: Bool
    /// Where the app must be for an in-app install. Default: ``InstallLocation/inPlace``.
    public var installLocation: InstallLocation
    /// Prefix for the keys OnePercent stores in `UserDefaults`. Default: `"OnePercent."`.
    /// The full list is ``OnePercentUpdater/storedKeys(configuration:)`` — remove them when your app resets itself.
    public var defaultsKeyPrefix: String
    /// The `User-Agent` header. Default: `<appName>/<installed version>`.
    public var userAgent: String?
    /// Size and time limits for the download and the archive.
    public var limits: Limits
    /// Hosts that requests and redirects may reach. HTTPS only.
    public var allowedHosts: Set<String>
    /// Allow the administrator-password install (an app the user cannot write, for example installed with `sudo` or used
    /// from a standard account). Default: `false`.
    /// 2026-11-20 오너 결정(A): 보안 리뷰 P1-1 수정은 넣었지만 실제 Mac 의 암호 창으로 아직 해 보지 않았다 — 실기기 확인
    /// (docs/MANUAL-TEST.md 2·3번) 전까지 기본으로 끈다. 꺼져 있으면 앱 안 설치 대신 릴리스 페이지에서 직접 바꾸라고 안내한다.
    public var allowsAdministratorInstall: Bool
    /// A repository to use **instead** of ``repository`` while testing. Set it only inside your own `#if DEBUG`;
    /// OnePercent also ignores it unless it was itself built for debugging. Signature, notarization and version checks still apply.
    /// 2026-11-20 (PR #1 보안 리뷰 P3-6): 예전엔 UserDefaults 키 두 개로 켰다 — 같은 사용자 코드가 `defaults write`(전역 도메인 포함)로
    /// 저장소를 돌릴 수 있었다. 이제는 앱이 코드로만 켠다.
    public var testRepository: String?

    public init(
        repository: String,
        teamIdentifier: String,
        bundleIdentifier: String,
        appName: String,
        versionScheme: VersionScheme = .numeric,
        tagPrefix: String = "",
        assetName: (@Sendable (_ tag: String) -> String)? = nil,
        versionSuffixInfoKey: String? = nil,
        requireBuildIncrease: Bool = true,
        schedule: CheckSchedule = .monthly,
        automaticChecksByDefault: Bool = true,
        installLocation: InstallLocation = .inPlace,
        defaultsKeyPrefix: String = "OnePercent.",
        userAgent: String? = nil,
        limits: Limits = .standard,
        allowedHosts: Set<String> = OnePercentConfiguration.githubHosts
    ) {
        self.repository = repository
        self.teamIdentifier = teamIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.versionScheme = versionScheme
        self.tagPrefix = tagPrefix
        self.assetName = assetName
        self.versionSuffixInfoKey = versionSuffixInfoKey
        self.requireBuildIncrease = requireBuildIncrease
        self.schedule = schedule
        self.automaticChecksByDefault = automaticChecksByDefault
        self.installLocation = installLocation
        self.defaultsKeyPrefix = defaultsKeyPrefix
        self.userAgent = userAgent
        self.limits = limits
        self.allowedHosts = allowedHosts
        self.testRepository = nil
        self.allowsAdministratorInstall = false
    }

    /// GitHub's API host, the release page host and the asset CDN hosts.
    /// 2026-09-21 실측(하늘키보드): `github.com/…/releases/download/…` → 302 → `release-assets.githubusercontent.com`.
    /// `objects.githubusercontent.com` 도 남겨 둔다 — GitHub 가 자산 CDN 을 바꿔도 한쪽은 맞게.
    public static let githubHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]

    /// The `.app` folder name inside the release ZIP.
    public var appFolderName: String { appName + ".app" }

    /// The asset file name OnePercent downloads for `tag`.
    public func assetFileName(forTag tag: String) -> String {
        assetName?(tag) ?? "\(appName)_\(tag).zip"
    }

    /// Problems that make the configuration unusable. Empty means valid.
    /// OnePercent refuses to check or install while this is not empty.
    public var problems: [String] {
        var list: [String] = []
        if !Self.isValidRepository(repository) { list.append("repository must be owner/name") }
        if let testRepository, !Self.isValidRepository(testRepository) { list.append("testRepository must be owner/name") }
        if !Self.isValidTeam(teamIdentifier) { list.append("teamIdentifier must be 10 uppercase letters or digits") }
        if !Self.isValidBundleIdentifier(bundleIdentifier) { list.append("bundleIdentifier has unsupported characters") }
        if !Self.isValidAppName(appName) { list.append("appName must be a plain file name") }
        if tagPrefix.contains(where: { !Self.isTagCharacter($0) }) { list.append("tagPrefix has unsupported characters") }
        if allowedHosts.isEmpty { list.append("allowedHosts is empty") }
        if limits.maxAssetBytes <= 0 || limits.maxMetadataBytes <= 0 { list.append("limits must be positive") }
        return list
    }

    // MARK: - Validation rules (values are inserted into URLs, code requirements and a shell script)

    /// `owner/name`, each part ASCII letters, digits, `-`, `_` or `.`, not `.` or `..`.
    static func isValidRepository(_ slug: String) -> Bool {
        let parts = slug.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        for part in parts {
            guard !part.isEmpty, part.count <= 100, part != ".", part != "..",
                  part.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") })
            else { return false }
        }
        return true
    }

    /// Apple Team IDs are 10 uppercase ASCII letters or digits. Anything else could change the meaning of a code requirement.
    static func isValidTeam(_ team: String) -> Bool {
        team.utf8.count == 10 && team.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
    }

    /// Reverse-DNS letters, digits, `.` and `-` only — no quotes, spaces or control characters.
    static func isValidBundleIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.count <= 255 && !identifier.hasPrefix(".") && !identifier.hasSuffix(".")
            && identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    /// A single file name: no `/`, NUL, newline, leading `.` or `..`.
    static func isValidAppName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 200 && !name.hasPrefix(".")
            && !name.contains("/") && !name.contains("\0") && !name.contains("\n") && !name.contains("\r")
    }

    static func isTagCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "-" || character == "_")
    }
}

/// How often the background check asks GitHub.
public enum CheckSchedule: Sendable, Equatable {
    /// Once per calendar month: the first time the app is running on or after the 1st (local time).
    case monthly
    /// Once every 7 days.
    case weekly
    /// Once every 24 hours.
    case daily
    /// Once every given number of seconds (at least one hour).
    case every(TimeInterval)
    /// Never in the background. Only ``OnePercentUpdater/checkNow(userInitiated:showNotice:)`` asks.
    case manual
}

/// Where the app must be running from for an in-app install.
public enum InstallLocation: Sendable, Equatable {
    /// Replace the running app wherever it is — as long as macOS is not running it from a temporary,
    /// read-only copy (App Translocation) or from a read-only disk such as a disk image.
    case inPlace
    /// Only when running as `/Applications/<appName>.app` (not a subfolder, not renamed).
    case applicationsFolder
}

/// Size and time limits. The defaults leave several times the room a typical app needs.
public struct Limits: Sendable, Equatable {
    /// Largest release ZIP accepted, enforced while downloading.
    public var maxAssetBytes: Int
    /// Largest GitHub release JSON accepted.
    public var maxMetadataBytes: Int
    /// Limits while unpacking the ZIP.
    public var archive: ArchiveLimits

    public init(maxAssetBytes: Int, maxMetadataBytes: Int, archive: ArchiveLimits) {
        self.maxAssetBytes = maxAssetBytes
        self.maxMetadataBytes = maxMetadataBytes
        self.archive = archive
    }

    /// 500 MiB download, 2 MiB metadata, ``ArchiveLimits/standard``. Small apps may tighten these.
    /// 2026-11-20: 하늘키보드는 200 MiB 였다. 여러 앱이 쓰는 기본값이라 넓혔다(Electron 류 앱의 ZIP 은 수백 MB).
    public static let standard = Limits(maxAssetBytes: 500 * 1024 * 1024, maxMetadataBytes: 2 * 1024 * 1024, archive: .standard)
}

/// Limits while unpacking. The ZIP's own size fields cannot be trusted, so these are measured on disk during extraction.
///
/// 근거(2026-11-13 하늘키보드 실측, 후보 111 ZIP): 항목 221개, 풀린 크기 81,828,760바이트, `ditto -x -k` 0.20초.
/// 2026-11-20: 하늘키보드 상한(2,000개·512 MiB·120초)을 그대로 쓰니 실제 Developer ID 앱(Ghostty 1.4.0, 항목 2,283개)이 거부됐다.
/// 여러 앱이 쓰는 기본값이라 넓혔다. 디스크를 채우는 압축 폭탄은 여전히 2 GiB 에서 멈춘다.
public struct ArchiveLimits: Sendable, Equatable {
    /// Most entries in the ZIP listing and most items on disk while unpacking.
    public var entries: Int
    /// Most bytes on disk while unpacking.
    public var bytes: UInt64
    /// Longest time unpacking may take.
    public var seconds: TimeInterval

    public init(entries: Int, bytes: UInt64, seconds: TimeInterval) {
        self.entries = entries
        self.bytes = bytes
        self.seconds = seconds
    }

    /// 50,000 entries, 2 GiB, 300 seconds.
    public static let standard = ArchiveLimits(entries: 50_000, bytes: 2 * 1024 * 1024 * 1024, seconds: 300)
}
