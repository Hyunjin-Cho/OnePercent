import Foundation
import Security
import Testing
@testable import OnePercent

@Suite struct DecisionTests {
    let config = Fixture.configuration()

    // MARK: - Configuration

    @Test func configurationValidation() {
        #expect(config.problems.isEmpty)
        var bad = config
        bad.repository = "owner/../x"
        #expect(!bad.problems.isEmpty)
        for team in ["", "short", "ABCDE12345\" or true", "abcde12345", "ABCDE123456"] {
            var c = config; c.teamIdentifier = team
            #expect(!c.problems.isEmpty, "team \(team)")
        }
        for id in ["", "com.example\"x", "com example", ".com.x", "com.x."] {
            var c = config; c.bundleIdentifier = id
            #expect(!c.problems.isEmpty, "bundle \(id)")
        }
        for name in ["", ".Hidden", "a/b", "a\nb"] {
            var c = config; c.appName = name
            #expect(!c.problems.isEmpty, "name \(name)")
        }
        var prefix = config; prefix.tagPrefix = "v/"
        #expect(!prefix.problems.isEmpty)
        #expect(config.assetFileName(forTag: "1.2") == "TestApp_1.2.zip")
        var custom = config; custom.assetName = { "test-\($0).zip" }
        #expect(custom.assetFileName(forTag: "1.2") == "test-1.2.zip")
    }

    @Test func storedKeysUseThePrefix() {
        var c = config; c.defaultsKeyPrefix = "pomolight.update."
        let keys = OnePercentUpdater.storedKeys(configuration: c)
        #expect(keys.count == 5 && keys.allSatisfy { $0.hasPrefix("pomolight.update.") })
    }

    // MARK: - Schedule

    @Test func monthlyScheduleChecksOnTheFirst() {
        let calendar = UpdateDecision.checkCalendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        let lastMonth = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23))!
        let thisMonth = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 5))!
        func due(_ last: Date?, enabled: Bool = true, forced: Bool = false) -> Bool {
            UpdateDecision.shouldCheckNow(schedule: .monthly, automaticChecksEnabled: enabled, lastCheck: last, now: now, forced: forced)
        }
        #expect(due(nil), "never checked")
        #expect(due(lastMonth), "last check before the 1st")
        #expect(!due(thisMonth), "already checked this month")
        #expect(!due(lastMonth, enabled: false), "switch off")
        #expect(due(thisMonth, enabled: false, forced: true), "the user asked")
        #expect(due(now.addingTimeInterval(3600)), "clock went backwards")
    }

    @Test func intervalSchedules() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func due(_ schedule: CheckSchedule, ago: TimeInterval) -> Bool {
            UpdateDecision.shouldCheckNow(schedule: schedule, automaticChecksEnabled: true, lastCheck: now.addingTimeInterval(-ago), now: now, forced: false)
        }
        #expect(!due(.daily, ago: 23 * 3600) && due(.daily, ago: 24 * 3600))
        #expect(due(.daily, ago: 24 * 3600 - 120), "a few minutes of slack, so an hourly tick does not push it to 25 hours")
        #expect(!due(.weekly, ago: 6 * 86400) && due(.weekly, ago: 7 * 86400))
        #expect(!due(.every(60), ago: 50 * 60), "at least one hour, whatever was asked")
        #expect(due(.every(60), ago: 3600) && due(.every(3600), ago: 3600 - 120))
        #expect(!due(.manual, ago: 365 * 86400), "manual never checks in the background")
        #expect(UpdateDecision.shouldCheckNow(schedule: .manual, automaticChecksEnabled: true, lastCheck: nil, now: now, forced: true))
    }

    // MARK: - Versions

    @Test func bundleVersionWithSuffix() {
        let calendar = Fixture.configuration(scheme: .calendar(), suffixKey: "ReleaseSuffix")
        #expect(UpdateDecision.bundleVersion(info: ["CFBundleShortVersionString": "2026.11.17", "ReleaseSuffix": "_hotfix2"],
                                             configuration: calendar) == "2026.11.17_hotfix2")
        #expect(UpdateDecision.bundleVersion(info: ["CFBundleShortVersionString": "2026.11.17"], configuration: calendar) == "2026.11.17")
        #expect(UpdateDecision.bundleVersion(info: ["CFBundleShortVersionString": "2026.11.17", "ReleaseSuffix": 3],
                                             configuration: calendar) == nil, "a suffix that is not text")
        #expect(UpdateDecision.bundleVersion(info: ["CFBundleShortVersionString": "2026.11.17", "ReleaseSuffix": "_beta"],
                                             configuration: calendar) == nil, "an unknown suffix")
        #expect(UpdateDecision.bundleVersion(info: [:], configuration: config) == nil)
    }

    @Test func versionAndBuildMustBothIncrease() {
        func increase(_ cv: String, _ cb: String?, _ nv: String?, _ nb: String?, _ c: OnePercentConfiguration? = nil) -> Bool {
            UpdateDecision.isVersionIncrease(currentVersion: cv, currentBuild: cb, newVersion: nv, newBuild: nb, configuration: c ?? config)
        }
        #expect(increase("1.0", "1", "1.1", "2"))
        #expect(!increase("1.0", "5", "1.1", "4"), "build went down")
        #expect(!increase("1.0", "5", "1.1", "5"), "same build")
        #expect(!increase("1.1", "1", "1.0", "2"), "version went down")
        #expect(!increase("1.0", nil, "1.1", "2"), "unreadable current build")
        #expect(!increase("1.0", "1", nil, "2"), "unreadable new version")
        #expect(increase("1.0", "1.9", "1.1", "1.10"), "dotted build numbers compare as numbers")
        #expect(increase("1.0", nil, "1.1", nil, Fixture.configuration(requireBuildIncrease: false)), "build check can be turned off")
        #expect(increase("1.0", "202611191200", "1.1", "202611201530"), "date-time build numbers (12 digits)")
        func problem(_ cv: String, _ cb: String?, _ nv: String?, _ nb: String?) -> VerificationFailure? {
            UpdateDecision.increaseProblem(currentVersion: cv, currentBuild: cb, newVersion: nv, newBuild: nb, configuration: config)
        }
        #expect(problem("1.0", "1", "1.1", "2") == nil)
        #expect(problem("1.1", "1", "1.0", "2") == .versionNotHigher)
        #expect(problem("1.0", "5", "1.1", "5") == .buildNotHigher, "forgot to raise CFBundleVersion — its own reason")
        #expect(problem("1.0", "1", "1.1", "2b") == .buildUnreadable)
        #expect(problem("1.0", nil, "1.1", "2") == .buildUnreadable)
    }

    /// 2026-11-13 (하늘키보드 #226 F-1): 받은 앱은 안내한 바로 그 버전이어야 한다.
    @Test func bundleMustMatchTheAnnouncedRelease() {
        let calendar = Fixture.configuration(scheme: .calendar())
        func matches(_ bundle: String?, _ release: String) -> Bool {
            UpdateDecision.bundleMatchesRelease(bundleVersion: bundle, releaseVersion: release, configuration: calendar)
        }
        #expect(matches("2026.12.01", "2026.12.01"))
        #expect(matches("2026.12.1", "2026.12.01"), "zero padding only")
        #expect(matches("2026.12.01_hotfix2", "2026.12.01_hotfix2"))
        #expect(!matches("2026.11.20", "2026.12.01"), "an older build on a newer tag")
        #expect(!matches("2027.01.01", "2026.12.01"), "a newer build is also refused")
        #expect(!matches("2026.12.01", "2026.12.01_hotfix1"))
        #expect(!matches("2026.12.01_hotfix1", "2026.12.01_hotfix2"))
        #expect(!matches(nil, "2026.12.01"))
    }

    @Test func justUpdatedNeedsARecordedLowerVersion() {
        func updated(_ current: String, _ last: String?) -> String? {
            UpdateDecision.justUpdatedVersion(current: current, lastLaunched: last, configuration: config)
        }
        #expect(updated("1.1", "1.0") == "1.1")
        #expect(updated("1.1", "1.1") == nil, "same version again")
        #expect(updated("1.0", "1.1") == nil, "went down")
        #expect(updated("1.1", nil) == nil, "first launch with OnePercent is a fresh install")
        #expect(updated("1.1", "broken") == nil)
        #expect(updated("v1.1", "1.0") == nil)
    }

    // MARK: - Location

    @Test func installTargetInPlace() {
        func target(_ path: String, readOnly: Bool = false, _ c: OnePercentConfiguration? = nil) -> Result<String, OnePercentError> {
            UpdateDecision.installTarget(runningBundlePath: path, configuration: c ?? config, isReadOnlyVolume: readOnly)
        }
        #expect(target("/Applications/TestApp.app") == .success("/Applications/TestApp.app"))
        #expect(target("/Users/me/Downloads/TestApp 2.app") == .success("/Users/me/Downloads/TestApp 2.app"), "anywhere, renamed")
        #expect(target("/private/var/folders/x/AppTranslocation/ABC/d/TestApp.app") == .failure(.translocated))
        #expect(target("/Volumes/TestApp/TestApp.app", readOnly: true) == .failure(.readOnlyVolume))
        if case .failure(.notAtRequiredLocation) = target("/usr/local/bin/testapp") {} else { Issue.record("not an app bundle") }
        #expect(target("/private/var/folders/x/TestApp.app") == .success("/private/var/folders/x/TestApp.app"), "the path is used as given")
        #expect(target("/Applications/TestApp.app/") == .success("/Applications/TestApp.app"))
        for odd in ["/Applications/../tmp/TestApp.app", "/Applications/./TestApp.app", "/Applications//TestApp.app", "TestApp.app"] {
            if case .failure(.notAtRequiredLocation) = target(odd) {} else { Issue.record("\(odd) should be refused") }
        }
        let strict = Fixture.configuration(location: .applicationsFolder)
        #expect(target("/Applications/TestApp.app", strict) == .success("/Applications/TestApp.app"))
        for path in ["/Applications/Tools/TestApp.app", "/Applications/TestApp 2.app", "/Users/me/Applications/TestApp.app"] {
            if case .failure(.notAtRequiredLocation(let required, _)) = target(path, strict) {
                #expect(required == "/Applications/TestApp.app")
            } else { Issue.record("\(path) should be refused") }
        }
    }

    /// 2026-09-21 (하늘키보드 #19 P3-1).
    @Test func safeExtractedApp() {
        let root = "/private/tmp/x/extract"
        func safe(link: Bool = false, dir: Bool = true, _ app: String, _ base: String = root) -> Bool {
            UpdateDecision.isSafeExtractedApp(isSymbolicLink: link, isDirectory: dir, resolvedAppPath: app, resolvedExtractDirPath: base)
        }
        #expect(safe(root + "/TestApp.app"))
        #expect(safe(root + "/TestApp.app", root + "/"))
        #expect(!safe(link: true, root + "/TestApp.app"))
        #expect(!safe(dir: false, root + "/TestApp.app"))
        #expect(!safe("/Applications/TestApp.app"), "resolved outside")
        #expect(!safe(root + "/../TestApp.app"))
        #expect(!safe(root + "x/TestApp.app"), "a sibling folder with the same prefix")
        #expect(!safe(root + "/TestApp.app", "/"), "root as extraction folder")
        #expect(!safe(root, root))
    }

    @Test func replaceStrategy() {
        func strategy(_ owner: UInt32?, parent: UInt32?, writable: Bool) -> UpdateDecision.ReplaceStrategy {
            UpdateDecision.replaceStrategy(destinationOwnerUID: owner, parentOwnerUID: parent, currentUID: 501, parentWritable: writable)
        }
        #expect(strategy(501, parent: 0, writable: true) == .userAtomic, "/Applications as an admin user")
        #expect(strategy(0, parent: 0, writable: true) == .adminPrompt, "installed by sudo")
        #expect(strategy(501, parent: 0, writable: false) == .adminPrompt, "standard account")
        #expect(strategy(nil, parent: 0, writable: true) == .adminPrompt)
        // 2026-11-20 (보안 리뷰 P1-1): 내 폴더 안이면 쓰기 권한을 막아 둬도 관리자 경로로 가지 않는다.
        #expect(strategy(501, parent: 501, writable: false) == .userAtomic)
        #expect(strategy(0, parent: 501, writable: true) == .userAtomic)
    }

    /// 2026-11-20: 모든 서명 검사가 같은 요구사항 하나를 쓴다 — Apple 사슬, 번들 ID, Developer ID 표시 두 개, 팀.
    @Test func oneCodeRequirement() {
        let text = UpdateDecision.codeRequirement(bundleIdentifier: Fixture.bundleID, team: Fixture.team)
        #expect(text == "anchor apple generic and identifier \"com.example.testapp\" and certificate 1[field.1.2.840.113635.100.6.2.6] "
                + "and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"ABCDE12345\"")
        var requirement: SecRequirement?
        #expect(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, "Security.framework compiles it")
        let arguments = UpdateDecision.codesignArguments(appPath: "/x/TestApp.app", requirement: text)
        #expect(arguments == ["--verify", "--deep", "--strict", "--all-architectures", "-R=\(text)", "/x/TestApp.app"])
    }

    @Test func unsignedBundlesFailTheSecurityCheck() throws {
        let root = try Fixture.temporaryRoot("unsigned")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try Fixture.makeApp(root.appendingPathComponent("TestApp.app"), version: "1.0", build: "1")
        let requirement = UpdateDecision.codeRequirement(bundleIdentifier: Fixture.bundleID, team: Fixture.team)
        #expect(!BundleTrust.satisfies(app, requirement: requirement))
        #expect(!BundleChecks.live.codesignValid(app, requirement))
        #expect(!BundleChecks.live.notarizationAccepted(app))
    }

    // MARK: - Korean particle

    @Test func koreanParticleFollowsTheLastSound() {
        let cases: [(String, String)] = [("2026.11.17", "로"), ("2026.11.18", "로"), ("2026.11.19", "로"), ("2026.11.20", "으로"),
                                         ("2026.11.23", "으로"), ("2026.11.26", "으로"), ("1.1", "로"), ("1.0", "으로"),
                                         ("2026.11.17_hotfix10", "으로"), ("한글", "로"), ("버전", "으로"), ("beta", "(으)로"), ("", "(으)로")]
        for (text, particle) in cases { #expect(L10n.koreanDirectionalParticle(after: text) == particle, "\(text)") }
    }
}
