import Testing
@testable import OnePercent

@Suite struct VersionSchemeTests {
    @Test func numericReadsOneToFourParts() {
        let scheme = VersionScheme.numeric
        for valid in ["1", "1.0", "1.2.3", "2026.11.17", "1.0.0.1", "0.9"] { #expect(scheme.isValid(valid), "\(valid)") }
        for invalid in ["", "v1.0", "1.", ".1", "1..2", "1.2.3.4.5", "1.0-beta", "１.０", "1.0 ", "-1", "1234567890"] {
            #expect(!scheme.isValid(invalid), "\(invalid)")
        }
    }

    @Test func numericOrdersPartByPart() {
        let scheme = VersionScheme.numeric
        #expect(scheme.isNewer("1.0.1", than: "1.0"))
        #expect(scheme.isNewer("1.10", than: "1.9"), "numbers, not text")
        #expect(scheme.isNewer("2", than: "1.99.99"))
        #expect(scheme.isSame("1", "1.0.0"), "missing parts are zero")
        #expect(scheme.isSame("1.01", "1.1"), "leading zeros do not matter")
        #expect(!scheme.isNewer("1.0", than: "1.0"))
        #expect(!scheme.isNewer("0.9", than: "1.0"))
        #expect(scheme.compare("v2", "1") == nil, "invalid never compares")
        #expect(!scheme.isNewer("v2", than: "1"), "an unreadable version is never newer")
    }

    /// 2026-11-20: 하늘키보드 `CalVer` 규칙과 같다(2026-11-04 #131 번호 붙은 핫픽스).
    @Test func calendarMatchesHaneulKeyboardRules() {
        let scheme = VersionScheme.calendar()
        for valid in ["2026.11.17", "2026.8", "2026.11.17_hotfix1", "2026.11.17_hotfix999", "2026.12.1"] {
            #expect(scheme.isValid(valid), "\(valid)")
        }
        for invalid in ["v2026.08", "2026", "2026.08.1.2", "2026..08", "2026.-1", "2026.11.17_hotfix", "2026.11.17_hotfix0",
                        "2026.11.17_hotfix01", "2026.11.17_HOTFIX1", "2026.11_hotfix1", "2026.02.30_hotfix1", "2026.11.7_hotfix1"] {
            #expect(!scheme.isValid(invalid), "\(invalid)")
        }
        #expect(scheme.isNewer("2026.11.17_hotfix1", than: "2026.11.17"))
        #expect(scheme.isNewer("2026.11.17_hotfix10", than: "2026.11.17_hotfix9"))
        #expect(scheme.isNewer("2026.11.18", than: "2026.11.17_hotfix3"))
        #expect(scheme.isSame("2026.12.1", "2026.12.01"))
        #expect(scheme.isNewer("2026.11.17", than: "2026.9"), "older two-part numbers still compare")
    }

    @Test func customSchemeIsFree() {
        // "build-<n>" — any rule the app wants.
        let scheme = VersionScheme(name: "build") { text in
            guard text.hasPrefix("build-"), let n = Int(text.dropFirst(6)) else { return nil }
            return [n]
        }
        #expect(scheme.isNewer("build-12", than: "build-9"))
        #expect(!scheme.isValid("12"))
    }
}
