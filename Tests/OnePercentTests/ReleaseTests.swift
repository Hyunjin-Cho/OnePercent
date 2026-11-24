import Foundation
import Testing
@testable import OnePercent

@Suite struct ReleaseTests {
    let config = Fixture.configuration()
    let hosts = OnePercentConfiguration.githubHosts

    func json(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    func release(tag: String = "1.1", assetName: String? = nil, url: String? = nil, size: Int = 100,
                 digest: Any? = nil, draft: Bool = false, prerelease: Bool = false, page: String? = nil) -> Data {
        var asset: [String: Any] = ["name": assetName ?? "TestApp_\(tag).zip", "size": size,
                                    "browser_download_url": url ?? "https://github.com/owner/TestApp/releases/download/\(tag)/TestApp_\(tag).zip"]
        if let digest { asset["digest"] = digest }
        return json(["tag_name": tag, "draft": draft, "prerelease": prerelease, "body": "Notes",
                     "html_url": page ?? "https://github.com/owner/TestApp/releases/tag/\(tag)", "assets": [asset]])
    }

    @Test func parsesOnlyWhatIsNeeded() throws {
        let info = try #require(ReleaseDecision.parseRelease(release(), allowedHosts: hosts))
        #expect(info.tag == "1.1" && info.assets.count == 1 && info.notes == "Notes")
        #expect(info.pageURL?.absoluteString == "https://github.com/owner/TestApp/releases/tag/1.1")
        #expect(ReleaseDecision.parseRelease(release(draft: true), allowedHosts: hosts) == nil)
        #expect(ReleaseDecision.parseRelease(release(prerelease: true), allowedHosts: hosts) == nil)
        #expect(ReleaseDecision.parseRelease(json(["draft": false]), allowedHosts: hosts) == nil, "no tag")
        #expect(ReleaseDecision.parseRelease(Data("not json".utf8), allowedHosts: hosts) == nil)
    }

    /// 2026-09-21 (하늘키보드 #19 P2-1): 릴리스 페이지 링크도 같은 문지기를 지난다.
    @Test func pageLinkMustBeAllowed() throws {
        for page in ["http://github.com/owner/TestApp", "https://evil.example/x", "javascript:alert(1)"] {
            let info = try #require(ReleaseDecision.parseRelease(release(page: page), allowedHosts: hosts))
            #expect(info.pageURL == nil, "\(page)")
        }
    }

    @Test func digestIsReadOnlyWhenWellFormed() throws {
        let hex = String(repeating: "ab", count: 32)
        #expect(ReleaseDecision.sha256(fromDigest: "sha256:" + hex) == hex)
        #expect(ReleaseDecision.sha256(fromDigest: "sha256:" + hex.uppercased()) == hex)
        for bad: Any? in [nil, NSNull(), "sha512:" + hex, "sha256:" + hex.dropLast(), "sha256:" + String(repeating: "zz", count: 32), 42] {
            #expect(ReleaseDecision.sha256(fromDigest: bad) == nil)
        }
        let info = try #require(ReleaseDecision.parseRelease(release(digest: "sha256:" + hex), allowedHosts: hosts))
        #expect(info.assets.first?.sha256 == hex)
    }

    @Test func assetMustMatchExactly() throws {
        func asset(_ data: Data) -> ReleaseAsset? {
            ReleaseDecision.parseRelease(data, allowedHosts: hosts).flatMap { ReleaseDecision.selectAsset(in: $0, configuration: config) }
        }
        #expect(asset(release()) != nil)
        #expect(asset(release(assetName: "TestApp_1.1.dmg")) == nil)
        #expect(asset(release(assetName: "testapp_1.1.zip")) == nil, "case matters")
        #expect(asset(release(url: "http://github.com/x.zip")) == nil)
        #expect(asset(release(url: "https://example.com/TestApp_1.1.zip")) == nil)
        #expect(asset(release(size: 600 * 1024 * 1024)) == nil, "over the size limit")
        // 2026-11-20 (보안 리뷰 P3-8): 다른 저장소의 자산 주소는 받지 않는다(대소문자는 GitHub 처럼 무시).
        #expect(asset(release(url: "https://github.com/evil/TestApp/releases/download/1.1/TestApp_1.1.zip")) == nil)
        #expect(asset(release(url: "https://github.com/OWNER/testapp/releases/download/1.1/TestApp_1.1.zip")) != nil)
        #expect(asset(release(url: "https://objects.githubusercontent.com/owner/TestApp/releases/download/1.1/TestApp_1.1.zip")) == nil,
                "the asset address itself is always github.com; CDN hosts are only reached by redirect")
        var dotted = config; dotted.assetName = { _ in "../x.zip" }
        let info = try #require(ReleaseDecision.parseRelease(release(assetName: "../x.zip"), allowedHosts: hosts))
        #expect(ReleaseDecision.selectAsset(in: info, configuration: dotted) == nil, "a path is never an asset name")
    }

    @Test func availableOnlyWhenNewerWithAnAsset() throws {
        let newer = try #require(ReleaseDecision.parseRelease(release(tag: "1.1"), allowedHosts: hosts))
        let update = try #require(ReleaseDecision.availableUpdate(currentVersion: "1.0", release: newer, configuration: config))
        #expect(update.tag == "1.1" && update.version == "1.1" && update.pageURL != nil)
        let foreignPage = try #require(ReleaseDecision.parseRelease(release(tag: "1.1", page: "https://github.com/evil/x/releases/tag/1.1"), allowedHosts: hosts))
        #expect(ReleaseDecision.availableUpdate(currentVersion: "1.0", release: foreignPage, configuration: config)?.pageURL == nil,
                "a release page of another repository is not linked")
        #expect(ReleaseDecision.availableUpdate(currentVersion: "1.1", release: newer, configuration: config) == nil)
        #expect(ReleaseDecision.availableUpdate(currentVersion: "1.2", release: newer, configuration: config) == nil)
        let missing = try #require(ReleaseDecision.parseRelease(release(tag: "1.1", assetName: "other.zip"), allowedHosts: hosts))
        #expect(ReleaseDecision.availableUpdate(currentVersion: "1.0", release: missing, configuration: config) == nil)
        let bad = try #require(ReleaseDecision.parseRelease(release(tag: "latest"), allowedHosts: hosts))
        #expect(ReleaseDecision.availableUpdate(currentVersion: "1.0", release: bad, configuration: config) == nil)
    }

    @Test func tagPrefix() throws {
        let prefixed = Fixture.configuration(tagPrefix: "v")
        let info = try #require(ReleaseDecision.parseRelease(release(tag: "v1.1"), allowedHosts: hosts))
        let update = try #require(ReleaseDecision.availableUpdate(currentVersion: "1.0", release: info, configuration: prefixed))
        #expect(update.tag == "v1.1" && update.version == "1.1")
        #expect(ReleaseDecision.availableUpdate(currentVersion: "1.0", release: info, configuration: config) == nil, "v1.1 is not a version")
        #expect(ReleaseDecision.version(fromTag: "1.1", configuration: prefixed) == nil, "the prefix is required")
    }

    @Test func releasePageFromTag() {
        #expect(ReleaseDecision.releasePageURL(tag: "1.1", configuration: config)?.absoluteString
                == "https://github.com/owner/TestApp/releases/tag/1.1")
        #expect(ReleaseDecision.releasePageURL(tag: "1.1/../x", configuration: config) == nil)
        #expect(ReleaseDecision.releasePageURL(tag: "latest", configuration: config) == nil)
        var bad = config; bad.repository = "evil/../repo"
        #expect(ReleaseDecision.releasePageURL(tag: "1.1", configuration: bad) == nil)
    }

    /// 2026-11-24 (#36): any host below githubusercontent.com — and nothing that only looks like one.
    @Test func wildcardHosts() {
        for allowed in ["https://release-assets.githubusercontent.com/a", "https://objects.githubusercontent.com/a",
                        "https://a-future-cdn.githubusercontent.com/a", "https://Deep.Sub.GitHubUserContent.com/a",
                        "https://github.com/a", "https://api.github.com/a"] {
            #expect(ReleaseDecision.isAllowedURL(URL(string: allowed)!, hosts: hosts), "\(allowed)")
        }
        for refused in ["https://githubusercontent.com/a", "https://evilgithubusercontent.com/a",
                        "https://githubusercontent.com.evil.example/a", "http://objects.githubusercontent.com/a",
                        "https://gist.github.com/a", "https://evil.example/a.githubusercontent.com"] {
            #expect(!ReleaseDecision.isAllowedURL(URL(string: refused)!, hosts: hosts), "\(refused)")
        }
        // 2026-11-24 (#50): `URL.host` decodes percent escapes — only host-name characters count.
        for encoded in ["https://evil.example%2F.githubusercontent.com/a", "https://evil%20x.githubusercontent.com/a"] {
            if let url = URL(string: encoded) { #expect(!ReleaseDecision.isAllowedURL(url, hosts: hosts), "\(encoded) → \(url.host ?? "nil")") }
        }
        #expect(!ReleaseDecision.isAllowedURL(URL(string: "https://objects.githubusercontent.com/a")!,
                                              hosts: ["github.com", "api.github.com", "release-assets.githubusercontent.com"]),
                "a list without the wildcard still matches exactly")
    }

    @Test func hostEntriesAreChecked() {
        for good: Set<String> in [OnePercentConfiguration.githubHosts, ["example.com"], ["*.cdn.example.com", "example.com"]] {
            var configuration = config; configuration.allowedHosts = good
            #expect(configuration.problems.isEmpty, "\(good)")
        }
        for bad: Set<String> in [["*.com"], ["*"], ["GitHub.com"], ["exa mple.com"], ["*.example..com"], [".example.com"], ["https://example.com"]] {
            var configuration = config; configuration.allowedHosts = bad
            #expect(configuration.problems.contains { $0.hasPrefix("allowedHosts entry") }, "\(bad)")
        }
    }
}
