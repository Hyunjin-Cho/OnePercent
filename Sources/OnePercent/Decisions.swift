import Foundation

/// Pure decisions — when to check, whether a bundle is newer, where to install, how to replace.
/// Everything here is deterministic and tested. When a decision is unclear it closes: no update, no install.
///
/// 2026-11-20: 하늘키보드 `UpdateDecisions.swift` 의 판단을 설정값으로 일반화해 옮겼다.
enum UpdateDecision {
    // MARK: - Schedule

    static var checkCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func startOfMonth(containing date: Date, calendar: Calendar = checkCalendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    /// The shortest interval allowed for ``CheckSchedule/every(_:)`` — GitHub allows 60 unauthenticated requests per hour per IP.
    static let minimumInterval: TimeInterval = 60 * 60
    /// Slack for interval schedules. 2026-11-20 (리뷰 P3-9): 확인 시각은 응답 때 찍히고 틱은 정시에 와서,
    /// 여유가 없으면 매일 확인이 25시간마다, 매시간 확인이 2시간마다가 됐다.
    static let scheduleSlack: TimeInterval = 5 * 60

    /// May OnePercent ask GitHub now?
    /// - `forced` (the user pressed "Check now"): always.
    /// - automatic checks off, or `.manual`: never in the background.
    /// - never checked, or the clock went backwards (last check in the future): yes.
    /// - otherwise by schedule. A user check also counts as the last check.
    static func shouldCheckNow(schedule: CheckSchedule, automaticChecksEnabled: Bool, lastCheck: Date?, now: Date,
                               forced: Bool, calendar: Calendar = checkCalendar) -> Bool {
        if forced { return true }
        guard automaticChecksEnabled, schedule != .manual else { return false }
        guard let lastCheck else { return true }
        if lastCheck > now { return true }
        switch schedule {
        case .monthly: return lastCheck < startOfMonth(containing: now, calendar: calendar)
        case .weekly: return now.timeIntervalSince(lastCheck) >= 7 * 24 * 60 * 60 - scheduleSlack
        case .daily: return now.timeIntervalSince(lastCheck) >= 24 * 60 * 60 - scheduleSlack
        case .every(let interval): return now.timeIntervalSince(lastCheck) >= max(interval, minimumInterval) - scheduleSlack
        case .manual: return false
        }
    }

    // MARK: - Versions

    /// The public version of a bundle: `CFBundleShortVersionString`, plus the optional signed suffix key.
    /// `nil` when missing, when the suffix is not a string, or when the result is not valid in the scheme.
    static func bundleVersion(info: [String: Any]?, configuration: OnePercentConfiguration) -> String? {
        guard let version = info?["CFBundleShortVersionString"] as? String else { return nil }
        var text = version
        if let key = configuration.versionSuffixInfoKey, let raw = info?[key] {
            guard let suffix = raw as? String else { return nil }
            text += suffix
        }
        return configuration.versionScheme.isValid(text) ? text : nil
    }

    /// Build numbers (`CFBundleVersion`): one to four dot-separated parts of up to 18 digits, so date-time builds such as
    /// `202611201530` work. 2026-11-20 (리뷰 P2-6): 예전엔 버전 규칙(마디당 9자리)으로 읽어 12자리 빌드가 늘 거부됐다.
    static let buildScheme = VersionScheme(name: "build") { text in
        VersionScheme.numericParts(text, allowedCounts: 1...4, maxDigits: 18)
    }

    /// Why the new bundle is not newer than the running one, or `nil` when it is. The version must increase, and —
    /// unless turned off — so must the build number. Anything unreadable: refused, with its own reason.
    static func increaseProblem(currentVersion: String, currentBuild: String?, newVersion: String?, newBuild: String?,
                                configuration: OnePercentConfiguration) -> VerificationFailure? {
        guard let newVersion, configuration.versionScheme.isNewer(newVersion, than: currentVersion) else { return .versionNotHigher }
        guard configuration.requireBuildIncrease else { return nil }
        guard let currentBuild, let newBuild, buildScheme.isValid(currentBuild), buildScheme.isValid(newBuild) else { return .buildUnreadable }
        return buildScheme.isNewer(newBuild, than: currentBuild) ? nil : .buildNotHigher
    }

    static func isVersionIncrease(currentVersion: String, currentBuild: String?, newVersion: String?, newBuild: String?,
                                  configuration: OnePercentConfiguration) -> Bool {
        increaseProblem(currentVersion: currentVersion, currentBuild: currentBuild, newVersion: newVersion, newBuild: newBuild,
                        configuration: configuration) == nil
    }

    /// Is the downloaded app exactly the release that was announced?
    /// 2026-11-13 (하늘키보드 #226 install-update-F-1): 상승만 보면, 새 태그에 그 사이의 다른 정식 빌드가 붙어 있어도
    /// 서명·공증·상승을 다 통과해 "새 버전"이라 안내한 채 다른 버전이 깔린다.
    static func bundleMatchesRelease(bundleVersion: String?, releaseVersion: String,
                                     configuration: OnePercentConfiguration) -> Bool {
        guard let bundleVersion else { return false }
        return configuration.versionScheme.isSame(bundleVersion, releaseVersion)
    }

    /// Did this launch follow an update? Returns the new version, or `nil`.
    /// OnePercent records the version at every launch; a launch with a higher version than the record is "just updated".
    /// No record yet means the first launch with OnePercent (a fresh install) — not an update.
    static func justUpdatedVersion(current: String, lastLaunched: String?, configuration: OnePercentConfiguration) -> String? {
        guard let lastLaunched, configuration.versionScheme.isValid(current) else { return nil }
        return configuration.versionScheme.isNewer(current, than: lastLaunched) ? current : nil
    }

    // MARK: - Location

    /// Where the update goes, or why it cannot be installed from here.
    /// - `.inPlace`: the running bundle — unless macOS runs it from a translocated copy or a read-only volume.
    /// - `.applicationsFolder`: only `/Applications/<appName>.app` exactly (하늘키보드 방식).
    static func installTarget(runningBundlePath: String, configuration: OnePercentConfiguration,
                              isReadOnlyVolume: Bool, applicationsDirectory: String = "/Applications") -> Result<String, OnePercentError> {
        // 2026-11-20: 경로를 다듬지 않는다. `standardizingPath`·`standardizedFileURL` 은 경로가 있으면 `/private` 를 떼어
        // `/var`(링크) 쪽 경로를 만든다 — 관리자 스크립트는 링크인 조상을 거부한다(시험에서 잡힘). 대신 이상한 꼴은 거부한다.
        var path = runningBundlePath
        while path.utf8.count > 1, path.utf8.last == 0x2F { path.removeLast() }
        // 바이트로 자른다(보안 리뷰 P3-2).
        let parts = Array(path.utf8).split(separator: 0x2F, omittingEmptySubsequences: false).dropFirst()
        guard path.utf8.first == 0x2F,
              !parts.contains(where: { $0.isEmpty || $0.elementsEqual([0x2E]) || $0.elementsEqual([0x2E, 0x2E]) }) else {
            return .failure(.notAtRequiredLocation(required: configuration.appFolderName, running: runningBundlePath))
        }
        // App Translocation: Gatekeeper 가 격리 표시가 남은 앱을 읽기 전용 임시 복사본으로 실행한다. 거기를 바꿔도 소용이 없다.
        if path.contains("/AppTranslocation/") { return .failure(.translocated) }
        if isReadOnlyVolume { return .failure(.readOnlyVolume) }
        switch configuration.installLocation {
        case .inPlace:
            guard path.hasSuffix(".app"), path.count > 1 else { return .failure(.notAtRequiredLocation(required: configuration.appFolderName, running: path)) }
            return .success(path)
        case .applicationsFolder:
            let required = (applicationsDirectory as NSString).appendingPathComponent(configuration.appFolderName)
            guard path == required else { return .failure(.notAtRequiredLocation(required: required, running: path)) }
            return .success(required)
        }
    }

    // MARK: - Extracted app

    /// Is the extracted `<appName>.app` a real folder inside the extraction folder?
    /// 2026-09-21 (하늘키보드 #19 P3-1): `ditto -x -k` 는 ZIP 의 링크 항목을 링크로 만든다. 그러면 뒤따르는 검사가 전부
    /// 링크가 가리키는 바깥 번들에 적용돼 통과하고, 교체 뒤에는 설치 위치가 그 링크가 된다.
    /// 두 경로는 같은 정규화(`resolvingSymlinksInPath().standardizedFileURL`)를 거친 값이어야 한다(`/var` ↔ `/private/var`).
    static func isSafeExtractedApp(isSymbolicLink: Bool, isDirectory: Bool,
                                   resolvedAppPath: String, resolvedExtractDirPath: String) -> Bool {
        guard !isSymbolicLink, isDirectory else { return false }
        var root = resolvedExtractDirPath
        while root.count > 1, root.hasSuffix("/") { root.removeLast() }
        guard root.hasPrefix("/"), root != "/" else { return false }
        guard !resolvedAppPath.contains("/../"), !resolvedAppPath.hasSuffix("/..") else { return false }
        return resolvedAppPath.hasPrefix(root + "/") && resolvedAppPath.count > root.count + 1
    }

    // MARK: - Replacement

    enum ReplaceStrategy: Equatable, Sendable {
        /// Owned by this user and the folder is writable: copy next to it, then swap in one step.
        case userAtomic
        /// Owned by someone else (often root) or the folder is not writable: ask for an administrator password.
        case adminPrompt
    }

    /// Unknown owner → the administrator path (if that fails the old app stays).
    /// 2026-11-20 (PR #1 보안 리뷰 P1-1): 부모 폴더가 이 사용자 것이면 절대 관리자 경로로 보내지 않는다 — 같은 사용자 코드가
    /// `chmod u-w` 한 번으로 root 경로를 강제할 수 있었다. 사용자 경로가 실패하면 그냥 실패한다.
    static func replaceStrategy(destinationOwnerUID: UInt32?, parentOwnerUID: UInt32?, currentUID: UInt32,
                                parentWritable: Bool) -> ReplaceStrategy {
        if parentOwnerUID == currentUID { return .userAtomic }
        guard let destinationOwnerUID, destinationOwnerUID == currentUID, parentWritable else { return .adminPrompt }
        return .userAtomic
    }

    // MARK: - Code requirement

    /// The one code requirement every signature check uses: an Apple-issued certificate chain, the configured bundle ID,
    /// a **Developer ID** certificate (the two Apple marker extensions), and the configured Team in the leaf certificate.
    /// 2026-09-21 (하늘키보드 #19 P1-1): OU 문자열만 비교하면 자체 서명 인증서로 위조할 수 있다. `anchor apple generic` 과 Team 을
    /// OS 수준에서 한 요구사항으로 묶어 막는다. 2026-11-20: 세 곳에 따로 있던 문자열을 하나로 합치고 첫 검사에도 번들 ID 를 넣었다(Fable 리뷰).
    /// 2026-11-20 (리서치 P1 — Sparkle·AppUpdater 와 같은 꼴): Developer ID 표시 두 개(중간 인증서 6.2.6, 잎 인증서 6.1.13)를 더해,
    /// 같은 팀의 개발용(Apple Development) 서명 빌드는 통과하지 못하게 좁혔다. 실측(이 Mac, 다른 회사 앱): Developer ID 앱 4개 통과,
    /// 팀만 바꾸면 전부 거부, App Store 서명 앱은 좁히기 전부터 거부. 같은 날 보안 리뷰(Fable 5.2)가 같은 팀의 Apple Development
    /// 서명 빌드로 재 봤다: 예전 꼴(팀+ID)은 통과(0), 지금 요구사항은 거부(3).
    /// Callers must pass validated values (``OnePercentConfiguration/problems`` is empty).
    static func codeRequirement(bundleIdentifier: String, team: String) -> String {
        "anchor apple generic and identifier \"\(bundleIdentifier)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]"
            + " and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// `codesign` arguments for the deep, strict check against ``codeRequirement(bundleIdentifier:team:)``.
    static func codesignArguments(appPath: String, requirement: String) -> [String] {
        ["--verify", "--deep", "--strict", "--all-architectures", "-R=\(requirement)", appPath]
    }
}
