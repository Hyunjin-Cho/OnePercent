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
        var dotted = config; dotted.assetName = { _ in "../x.zip" }
        let info = try #require(ReleaseDecision.parseRelease(release(assetName: "../x.zip"), allowedHosts: hosts))
        #expect(ReleaseDecision.selectAsset(in: info, configuration: dotted) == nil, "a path is never an asset name")
    }

    @Test func availableOnlyWhenNewerWithAnAsset() throws {
        let newer = try #require(ReleaseDecision.parseRelease(release(tag: "1.1"), allowedHosts: hosts))
        let update = try #require(ReleaseDecision.availableUpdate(currentVersion: "1.0", release: newer, configuration: config))
        #expect(update.tag == "1.1" && update.version == "1.1")
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
}
