import CryptoKit
import Foundation
import Testing
@testable import OnePercent

/// Everything that goes through the fake network. One serialized suite, because ``NetworkStub`` state is global.
/// 2026-11-20: 하늘키보드 `UpdaterTests`·`UpdateSecurityTests` 를 옮기고, Fable 리뷰가 없다고 짚은 것 — 내려받기 오류 분기,
/// 끝-끝 설치(확인 → 내려받기 → 검증 → 교체 → 재실행), 실패가 "새 버전 있음"을 지우지 않는지 — 를 더했다.
@Suite(.serialized) @MainActor struct NetworkTests {
    // MARK: - Harness

    @MainActor final class Harness {
        let store = MemoryStore()
        let gate = OperationGate()
        let session = NetworkStub.session()
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var version = "1.0"
        var build: String? = "1"
        // 2026-11-20 (리뷰 P3-20): 기본값도 실제 /Applications·$TMPDIR 이 아니라 없는 임시 경로 — noteLaunch 의 정리가 실제 폴더를 훑지 않게.
        var temporary = FileManager.default.temporaryDirectory.appendingPathComponent("onepercent-harness-\(UUID().uuidString)")
        lazy var installed = temporary.appendingPathComponent("Applications/TestApp.app")
        var firstCheckDelay: Duration = .seconds(15)
        var checks = BundleChecks.accepting
        var strategy = UpdateDecision.ReplaceStrategy.userAtomic
        var relaunched: [URL] = []
        var relaunchError: Error?
        var adminScripts: [AdminReplacementScript] = []
        var adminError: Error?
        var notices: [String] = []

        func make(_ configuration: OnePercentConfiguration = Fixture.configuration()) -> OnePercentUpdater {
            let environment = OnePercentUpdater.Environment(
                currentVersion: { [unowned self] _ in version },
                currentBuild: { [unowned self] in build },
                runningBundleURL: { [unowned self] in self.installed },
                applicationsDirectory: "/Applications",
                temporaryDirectory: temporary,
                checks: checks,
                strategy: { [unowned self] _ in strategy },
                verifyCopy: { UpdateReplacement.copyMatchesIdentity(at: $0, identity: $1) },
                adminReplace: { [unowned self] script in
                    adminScripts.append(script)
                    if let adminError { throw adminError }
                    return nil
                },
                relaunch: { [unowned self] url in
                    if let relaunchError { throw relaunchError }
                    relaunched.append(url)
                },
                firstCheckDelay: firstCheckDelay)
            let updater = OnePercentUpdater(configuration: configuration, store: store, session: session,
                                            now: { [unowned self] in now }, gate: gate, environment: environment)
            updater.onUpdateAvailable = { [unowned self] in notices.append($0.tag) }
            return updater
        }

        func nextMonth() {
            let calendar = UpdateDecision.checkCalendar
            now = calendar.date(byAdding: .month, value: 1, to: UpdateDecision.startOfMonth(containing: now))!
        }
    }

    func respond(_ tag: String, asset: Bool = true, status: Int = 200) {
        NetworkStub.set(ReleaseJSON.apiPath, .init(status: status, body: ReleaseJSON.body(tag: tag, asset: asset)))
    }

    var apiCount: Int { NetworkStub.count(ReleaseJSON.apiPath) }

    /// Waits for a condition with a limit, so a regression fails instead of hanging. 2026-11-20 (리뷰 P3-22).
    func waitUntil(_ label: String = "condition", seconds: Double = 5, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { Issue.record("timed out waiting for \(label)"); return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
    var keys: OnePercentUpdater.Keys { OnePercentUpdater.Keys("OnePercent.") }

    // MARK: - Checking and announcing

    @Test func automaticCheckAnnouncesOncePerVersion() async {
        NetworkStub.reset()
        let h = Harness()
        var updater = h.make()
        #expect(updater.automaticChecksEnabled, "on by default")
        #expect(updater.latestVersion == nil && updater.lastCheck == nil)
        respond("1.1")
        await updater.checkNow(userInitiated: false)
        #expect(h.notices == ["1.1"])
        #expect(updater.latestVersion == "1.1" && updater.lastCheck == h.now)
        #expect(h.store.object(forKey: keys.lastNotifiedVersion) as? String == "1.1")
        if case .available = updater.phase {} else { Issue.record("available, install not started: \(updater.phase)") }

        let first = apiCount
        h.nextMonth(); h.now.addTimeInterval(-1)
        await updater.checkNow(userInitiated: false)
        #expect(apiCount == first, "no request before the 1st")
        h.now.addTimeInterval(1)
        await updater.checkNow(userInitiated: false)
        #expect(apiCount == first + 1, "request on the 1st")
        #expect(h.notices.count == 1, "the same version is not announced again")

        updater = h.make()
        #expect(updater.latestVersion == "1.1" && updater.lastCheck == h.now, "restored after relaunch")
        h.nextMonth()
        respond("1.1.0")
        await updater.checkNow(userInitiated: false)
        #expect(h.notices.count == 1, "an equal version written differently is not announced again")
    }

    @Test func switchAndUserChecks() async {
        NetworkStub.reset()
        let h = Harness()
        let updater = h.make()
        respond("1.1")
        await updater.checkNow(userInitiated: false)
        updater.setAutomaticChecksEnabled(false)
        h.nextMonth()
        let off = apiCount
        await updater.checkNow(userInitiated: false)
        #expect(apiCount == off, "switch off: no background request")
        await updater.checkNow(userInitiated: true)
        #expect(apiCount == off + 1 && h.notices.count == 2, "a user check still asks and tells")
        await updater.checkNow(userInitiated: true)
        #expect(h.notices.count == 3, "a user check announces the same version again")
        #expect(!h.make().automaticChecksEnabled, "the switch is stored")
        updater.setAutomaticChecksEnabled(true)
        h.nextMonth()
        respond("1.2")
        await updater.checkNow(userInitiated: false)
        #expect(h.notices.last == "1.2" && h.notices.count == 4, "a different new version is announced")
    }

    @Test func failuresKeepTheLastSuccess() async {
        NetworkStub.reset()
        let h = Harness()
        let updater = h.make()
        respond("1.0")
        await updater.checkNow(userInitiated: false)
        #expect(updater.phase == .upToDate && h.notices.isEmpty)
        let success = updater.lastCheck
        h.nextMonth()
        for (status, code) in [(403, "rateLimited"), (404, "noRelease"), (429, "rateLimited"), (500, "httpStatus")] {
            respond("1.0", status: status)
            await updater.checkNow(userInitiated: false)
            #expect(updater.lastError?.code == code, "HTTP \(status)")
            #expect(updater.lastCheck == success && updater.latestVersion == "1.0", "HTTP \(status) keeps the last success")
        }
        respond("1.1")
        await updater.checkNow(userInitiated: false)
        #expect(h.notices == ["1.1"] && updater.lastError == nil, "recovers on the next check")
    }

    /// 2026-11-20 (Fable 리뷰 6): 실패가 "새 버전 있음"을 덮어쓰지 않는다.
    @Test func aFailureDoesNotHideAKnownUpdate() async {
        NetworkStub.reset()
        let h = Harness()
        let updater = h.make()
        respond("1.1")
        await updater.checkNow()
        respond("1.1", status: 500)
        await updater.checkNow()
        if case .available(let update) = updater.phase { #expect(update.tag == "1.1") } else { Issue.record("lost: \(updater.phase)") }
        #expect(updater.lastError == .httpStatus(500))
        #expect(updater.presentation.showsInstallButton && updater.presentation.error == .httpStatus(500))
    }

    /// 2026-11-20 (Fable 리뷰 5): 설치 파일이 아직 없는 새 태그는 확인 시각을 남기지 않아 다음 정시에 다시 묻는다.
    @Test func aTagWithoutItsZipIsCheckedAgain() async {
        NetworkStub.reset()
        let h = Harness()
        let updater = h.make()
        respond("1.0")
        await updater.checkNow(userInitiated: false)
        let success = updater.lastCheck
        h.nextMonth()
        respond("1.1", asset: false)
        await updater.checkNow(userInitiated: false)
        #expect(updater.lastError == .assetNotReady("1.1") && h.notices.isEmpty)
        #expect(updater.lastCheck == success, "not recorded as a successful check")
        #expect(updater.phase != .upToDate, "never shown as up to date")
        // 2026-11-20 (PR #1 리뷰 P2-4): 설치할 수 없는 버전을 최신 번호로 저장하지 않는다 — 설치 버튼이 남지 않는다.
        #expect(updater.latestVersion == "1.0" && !updater.presentation.showsInstallButton && !updater.presentation.showsMenuNotice)
        #expect(!h.make().presentation.showsInstallButton, "nor after a relaunch")
        h.now.addTimeInterval(3600)
        respond("1.1")
        let before = apiCount
        await updater.checkNow(userInitiated: false)
        #expect(apiCount == before + 1 && h.notices == ["1.1"], "the next hourly tick asks again and finds it")
    }

    @Test func malformedReleasesChangeNothing() async {
        NetworkStub.reset()
        let h = Harness()
        let updater = h.make()
        respond("1.1")
        await updater.checkNow()
        // 2026-11-20 (리뷰 P3-11): 버전이 아닌 태그는 서버 고장이 아니라 설정 문제로 알린다.
        for (body, code) in [(try! JSONSerialization.data(withJSONObject: ["tag_name": "2.0", "draft": true]), "malformedResponse"),
                             (try! JSONSerialization.data(withJSONObject: ["tag_name": "2.0", "prerelease": true]), "malformedResponse"),
                             (ReleaseJSON.body(tag: "bad-tag"), "badConfiguration"), (Data("{".utf8), "malformedResponse")] {
            NetworkStub.set(ReleaseJSON.apiPath, .init(body: body))
            await updater.checkNow()
            #expect(updater.lastError?.code == code)
            #expect(updater.latestVersion == "1.1" && h.notices.count == 1)
        }
        NetworkStub.set(ReleaseJSON.apiPath, .init(body: Data(count: 2 * 1024 * 1024 + 1)))
        await updater.checkNow()
        #expect(updater.lastError == .responseTooLarge(2 * 1024 * 1024))
    }

    @Test func noticeBookkeeping() async {
        NetworkStub.reset()
        let h = Harness()
        let updater = h.make()
        updater.onUpdateAvailable = nil
        respond("1.1")
        await updater.checkNow(userInitiated: false)
        #expect(h.store.object(forKey: keys.lastNotifiedVersion) == nil, "nothing shown, nothing recorded")
        updater.onUpdateAvailable = { h.notices.append($0.tag) }
        h.nextMonth()
        await updater.checkNow(userInitiated: false)
        #expect(h.notices == ["1.1"])

        // Shown in place (a settings screen): no popup, but counted as announced.
        let inline = Harness()
        let settings = inline.make()
        settings.setAutomaticChecksEnabled(false)
        respond("1.2")
        await settings.checkNow(userInitiated: true, showNotice: false)
        #expect(inline.notices.isEmpty)
        if case .available(let update) = settings.phase { #expect(update.tag == "1.2") } else { Issue.record("result lost") }
        settings.setAutomaticChecksEnabled(true)
        inline.nextMonth()
        await inline.make().checkNow(userInitiated: false)
        #expect(inline.notices.isEmpty, "no popup later for a version already shown")
    }

    /// 2026-10-25 (하늘키보드 #83): 조회 중 스위치를 끄면 늦은 응답도 알리지 않는다.
    @Test func switchingOffDuringACheck() async {
        NetworkStub.reset()
        let h = Harness()
        let updater = h.make()
        NetworkStub.set(ReleaseJSON.apiPath, .init(body: ReleaseJSON.body(tag: "1.1"), holdAfterChunks: 0))
        let check = Task { await updater.checkNow(userInitiated: false) }
        await waitUntil { NetworkStub.isHolding }
        updater.setAutomaticChecksEnabled(false)
        NetworkStub.release()
        await check.value
        #expect(h.notices.isEmpty && h.store.object(forKey: keys.lastNotifiedVersion) == nil)
        #expect(updater.latestVersion == "1.1" && updater.lastCheck == h.now, "what was received is kept")
        if case .available = updater.phase {} else { Issue.record("still available") }
    }

    @Test func oneRequestAtATime() async {
        NetworkStub.reset()
        let h = Harness()
        let updater = h.make()
        NetworkStub.set(ReleaseJSON.apiPath, .init(body: ReleaseJSON.body(tag: "1.1"), holdAfterChunks: 0))
        let first = Task { await updater.checkNow() }
        await waitUntil { NetworkStub.isHolding }
        await updater.checkNow()
        #expect(apiCount == 1)
        NetworkStub.release()
        await first.value
    }

    @Test func suspendIgnoresLateResponses() async {
        NetworkStub.reset()
        let h = Harness()
        let updater = h.make()
        NetworkStub.set(ReleaseJSON.apiPath, .init(body: ReleaseJSON.body(tag: "1.1"), holdAfterChunks: 0))
        let pending = Task { await updater.checkNow() }
        await waitUntil { NetworkStub.isHolding }
        #expect(updater.suspend())
        NetworkStub.release()
        await pending.value
        #expect(h.store.object(forKey: keys.lastCheck) == nil && h.store.object(forKey: keys.latestVersion) == nil)
        updater.setAutomaticChecksEnabled(false)
        #expect(updater.automaticChecksEnabled, "settings writes pause too")
        respond("1.1")
        await updater.checkNow()
        #expect(apiCount == 1, "no new request while suspended")
        updater.resume()
        await updater.checkNow()
        #expect(updater.latestVersion == "1.1")
        let token = h.gate.begin("app.reset")!
        await updater.checkNow()
        await updater.installAvailableUpdate()
        #expect(h.gate.operation == "app.reset" && updater.lastError == .busy, "the update never takes the app's gate")
        h.gate.finish(token)
    }

    @Test func launchBookkeeping() {
        let h = Harness()
        h.version = "1.1"
        h.store.set("1.0", forKey: keys.lastLaunchedVersion)
        let a = h.make()
        #expect(a.noteLaunch() == "1.1" && a.justUpdatedTo == "1.1")
        #expect(h.store.object(forKey: keys.lastLaunchedVersion) as? String == "1.1")
        #expect(h.make().noteLaunch() == nil, "same version again")
        let fresh = Harness()
        fresh.version = "1.1"
        #expect(fresh.make().noteLaunch() == nil, "fresh install")
        #expect(fresh.store.object(forKey: keys.lastLaunchedVersion) as? String == "1.1")
        let paused = Harness()
        let updater = paused.make()
        #expect(updater.suspend())
        #expect(updater.noteLaunch() == nil && paused.store.object(forKey: keys.lastLaunchedVersion) == nil)
    }

    /// 2026-11-13 (하늘키보드 #226 F-10): 앱이 넣는 헤더는 셋이다. Accept-Language 는 언어 목록이 나가지 않게 en 고정.
    @Test func requestHeaders() async {
        NetworkStub.reset()
        let h = Harness()
        respond("1.0")
        await h.make().checkNow()
        let headers = NetworkStub.lastHeaders(ReleaseJSON.apiPath) ?? [:]
        #expect(headers["Accept"] == "application/vnd.github+json")
        #expect(headers["User-Agent"] == "TestApp/1.0")
        #expect(headers["Accept-Language"] == "en")
        let request = h.make().request(for: URL(string: "https://api.github.com/x")!)
        #expect(Set((request.allHTTPHeaderFields ?? [:]).keys) == ["Accept", "User-Agent", "Accept-Language"])
        let config = OnePercentUpdater.sessionConfiguration()
        #expect(config.httpCookieAcceptPolicy == .never && !config.httpShouldSetCookies && config.httpAdditionalHeaders == nil)
    }

    // MARK: - Transport

    @Test func transportLimitsAndFiles() async throws {
        NetworkStub.reset()
        let root = try Fixture.temporaryRoot("transport")
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = NetworkStub.session().configuration
        let hosts = OnePercentConfiguration.githubHosts
        let url = URL(string: "https://api.github.com/t")!
        func receive(limit: Int = 8, to file: URL? = nil, _ url: URL = url) async throws -> Received {
            try await UpdateTransport.receive(URLRequest(url: url), configuration: configuration, limit: limit, allowedHosts: hosts, destination: file)
        }
        let chunk = Data([1, 2, 3, 4])
        NetworkStub.set("/t", .init(body: chunk + chunk, chunkSize: 4))
        #expect(try await receive().data == chunk + chunk, "exactly at the limit")

        let file = root.appendingPathComponent("update.zip")
        for length in [nil, 64 * 1024] as [Int?] {
            NetworkStub.set("/t", .init(body: Data(repeating: 1, count: 40 * 64 * 1024), chunkSize: 64 * 1024, contentLength: length))
            await #expect(throws: OnePercentError.responseTooLarge(128 * 1024)) { _ = try await receive(limit: 128 * 1024, to: file) }
            #expect(!FileManager.default.fileExists(atPath: file.path), "partial file removed (length \(String(describing: length)))")
        }

        let body = Data((0..<10_000).map { UInt8($0 % 251) })
        NetworkStub.set("/t", .init(body: body, chunkSize: 1000))
        let saved = try await receive(limit: 1 << 20, to: file)
        #expect(saved.data.isEmpty && (try? Data(contentsOf: file)) == body, "to disk, not memory")
        #expect(saved.sha256 == SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined(), "hashed while receiving")
        let mode = (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]) as? Int
        #expect(mode == 0o600)
        await #expect(throws: (any Error).self) { _ = try await receive(limit: 1 << 20, to: file) }
        #expect((try? Data(contentsOf: file)) == body, "an existing file is never overwritten")
        try FileManager.default.removeItem(at: file)

        NetworkStub.set("/t", .init(body: body, chunkSize: 1000, failAfterChunks: 3))
        await #expect(throws: (any Error).self) { _ = try await receive(limit: 1 << 20, to: file) }
        #expect(!FileManager.default.fileExists(atPath: file.path), "connection lost: partial file removed")

        for (address, shown) in [("http://api.github.com/t", "http://api.github.com"), ("https://example.com/t", "https://example.com")] {
            await #expect(throws: OnePercentError.redirectBlocked(shown)) { _ = try await receive(URL(string: address)!) }
        }
        NetworkStub.set("/target", .init(body: chunk))
        for (target, allowed) in [("https://release-assets.githubusercontent.com/target", true),
                                  ("https://example.com/target", false), ("http://github.com/target", false)] {
            NetworkStub.set("/t", .init(redirect: URL(string: target)!))
            if allowed { #expect(try await receive().data == chunk, "\(target)") }
            else { await #expect(throws: OnePercentError.redirectBlocked(ReleaseDecision.display(target))) { _ = try await receive() } }
        }
    }

    @Test func transportCancellation() async throws {
        NetworkStub.reset()
        let root = try Fixture.temporaryRoot("cancel")
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = NetworkStub.session().configuration
        let file = root.appendingPathComponent("update.zip")
        NetworkStub.set("/t", .init(body: Data(count: 4000), chunkSize: 1000, holdAfterChunks: 1))
        let pending = Task {
            try await UpdateTransport.receive(URLRequest(url: URL(string: "https://api.github.com/t")!), configuration: configuration,
                                              limit: 1 << 20, allowedHosts: OnePercentConfiguration.githubHosts, destination: file)
        }
        await waitUntil { NetworkStub.isHolding }
        pending.cancel()
        await #expect(throws: CancellationError.self) { _ = try await pending.value }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        NetworkStub.release()
        for _ in 0..<10 {
            let early = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await UpdateTransport.receive(URLRequest(url: URL(string: "https://api.github.com/t")!), configuration: configuration,
                                                         limit: 1 << 20, allowedHosts: OnePercentConfiguration.githubHosts, destination: file)
            }
            await #expect(throws: CancellationError.self) { _ = try await early.value }
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    // MARK: - End to end install (Fable 리뷰 2·3)

    struct Release {
        let root: URL
        let installed: URL
        let zip: Data
        var digest: String { SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined() }
    }

    /// Installed TestApp 1.0 (build 1, marker "old") and a real ditto ZIP of TestApp 1.1 (build 2, marker "new").
    func makeRelease(_ name: String, version: String = "1.1", build: String = "2") throws -> Release {
        let root = try Fixture.temporaryRoot(name)
        let installed = try Fixture.makeApp(root.appendingPathComponent("Applications/TestApp.app"), version: "1.0", build: "1", marker: "old")
        let source = try Fixture.makeApp(root.appendingPathComponent("src/TestApp.app"), version: version, build: build, marker: "new")
        let zipURL = root.appendingPathComponent("TestApp_\(version).zip")
        guard Fixture.zip(source, to: zipURL) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        return Release(root: root, installed: installed, zip: try Data(contentsOf: zipURL))
    }

    func serve(_ release: Release, tag: String = "1.1", size: Int? = nil, digest: String?? = nil, asset: NetworkStub.Reply? = nil) {
        let published: String? = switch digest { case .none: release.digest; case .some(let value): value }
        NetworkStub.set(ReleaseJSON.apiPath, .init(body: ReleaseJSON.body(tag: tag, size: size ?? release.zip.count, digest: published)))
        NetworkStub.set(ReleaseJSON.assetPath(tag), asset ?? .init(body: release.zip, chunkSize: 4096))
    }

    func harness(_ release: Release) -> Harness {
        let h = Harness()
        h.installed = release.installed
        h.temporary = release.root.appendingPathComponent("tmp")
        return h
    }

    func leftovers(_ release: Release) -> [String] {
        let fm = FileManager.default
        let tmp = (try? fm.contentsOfDirectory(atPath: release.root.appendingPathComponent("tmp").path)) ?? []
        let apps = (try? fm.contentsOfDirectory(atPath: release.installed.deletingLastPathComponent().path)) ?? []
        return tmp + apps.filter { $0 != "TestApp.app" }
    }

    @Test func installsAndReopens() async throws {
        NetworkStub.reset()
        let release = try makeRelease("e2e")
        defer { try? FileManager.default.removeItem(at: release.root) }
        serve(release)
        let h = harness(release)
        let updater = h.make()
        var saved = false
        updater.willRelaunch = { saved = true }
        await updater.checkNow()
        await updater.installAvailableUpdate()
        #expect(updater.lastError == nil, "\(String(describing: updater.lastError))")
        #expect(Fixture.marker(release.installed) == "new", "the new app is in place")
        #expect(h.relaunched.map(\.path) == [release.installed.path] && saved)
        #expect(leftovers(release).isEmpty, "no work folder, no staging: \(leftovers(release))")
        #expect(NetworkStub.count(ReleaseJSON.assetPath("1.1")) == 1)
    }

    @Test func downloadFailuresLeaveTheAppAlone() async throws {
        NetworkStub.reset()
        let release = try makeRelease("download-failures")
        defer { try? FileManager.default.removeItem(at: release.root) }
        let cases: [(String, () -> Void, OnePercentError)] = [
            ("HTTP 500", { serve(release, asset: .init(status: 500, body: Data("x".utf8))) }, .httpStatus(500)),
            ("size", { serve(release, size: release.zip.count + 1) }, .sizeMismatch(expected: release.zip.count + 1, actual: release.zip.count)),
            ("digest", { serve(release, digest: String(repeating: "0", count: 64)) }, .digestMismatch),
            ("redirect", { serve(release, asset: .init(redirect: URL(string: "https://example.com/x.zip")!)) }, .redirectBlocked("https://example.com")),
            ("cut", { serve(release, asset: .init(body: release.zip, chunkSize: 1024, failAfterChunks: 2)) }, .network("")),
        ]
        for (label, setUp, expected) in cases {
            setUp()
            let h = harness(release)
            let updater = h.make()
            await updater.checkNow()
            await updater.installAvailableUpdate()
            if case .network = expected { #expect(updater.lastError?.code == "network", "\(label)") }
            else { #expect(updater.lastError == expected, "\(label): \(String(describing: updater.lastError))") }
            if case .available = updater.phase {} else { Issue.record("\(label): the update must stay available") }
            #expect(Fixture.marker(release.installed) == "old" && h.relaunched.isEmpty, "\(label)")
            #expect(leftovers(release).isEmpty, "\(label): \(leftovers(release))")
        }
        // GitHub 가 지문을 안 준 옛 릴리스: 크기와 서명으로만 보고 설치한다.
        serve(release, digest: .some(nil))
        let h = harness(release)
        let updater = h.make()
        await updater.checkNow()
        await updater.installAvailableUpdate()
        #expect(updater.lastError == nil && Fixture.marker(release.installed) == "new", "no digest published")
    }

    @Test func refusalsBeforeAndAfterDownloading() async throws {
        NetworkStub.reset()
        let release = try makeRelease("guards")
        defer { try? FileManager.default.removeItem(at: release.root) }
        serve(release)
        let h = harness(release)
        let updater = h.make()
        await updater.checkNow()
        updater.installGuard = { "A timer is running." }
        await updater.installAvailableUpdate()
        #expect(updater.lastError == .blocked("A timer is running.") && NetworkStub.count(ReleaseJSON.assetPath("1.1")) == 0)
        var calls = 0
        updater.installGuard = { calls += 1; return calls == 1 ? nil : "Started meanwhile." }
        await updater.installAvailableUpdate()
        #expect(updater.lastError == .blocked("Started meanwhile."), "asked again right before replacing")
        #expect(Fixture.marker(release.installed) == "old" && leftovers(release).isEmpty)

        h.installed = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ID/d/TestApp.app")
        updater.installGuard = nil
        await updater.installAvailableUpdate()
        #expect(updater.lastError == .translocated)
    }

    @Test func verificationFailureLeavesTheAppAlone() async throws {
        NetworkStub.reset()
        let release = try makeRelease("verify")
        defer { try? FileManager.default.removeItem(at: release.root) }
        serve(release)
        let h = harness(release)
        h.checks = BundleChecks(signedByTeam: { _, _ in true }, codesignValid: { _, _ in false }, notarizationAccepted: { _ in true })
        let updater = h.make()
        await updater.checkNow()
        await updater.installAvailableUpdate()
        #expect(updater.lastError == .verificationFailed([.codeSignatureInvalid]))
        #expect(Fixture.marker(release.installed) == "old" && leftovers(release).isEmpty)
    }

    @Test func progressAndCancel() async throws {
        NetworkStub.reset()
        let release = try makeRelease("progress", version: "1.1")
        defer { try? FileManager.default.removeItem(at: release.root) }
        serve(release, asset: .init(body: release.zip, chunkSize: max(1, release.zip.count / 4), holdAfterChunks: 2))
        let h = harness(release)
        let updater = h.make()
        await updater.checkNow()
        let install = Task { await updater.installAvailableUpdate() }
        await waitUntil { NetworkStub.isHolding }
        for _ in 0..<200 {
            if case .downloading(let fraction?) = updater.phase, fraction > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        if case .downloading(let fraction?) = updater.phase { #expect(fraction > 0.2 && fraction < 1) } else { Issue.record("no progress: \(updater.phase)") }
        #expect(updater.presentation.showsCancelButton)
        updater.cancel()
        await install.value
        NetworkStub.release()
        #expect(updater.lastError == .cancelled)
        if case .available = updater.phase {} else { Issue.record("still available after cancel") }
        #expect(Fixture.marker(release.installed) == "old" && leftovers(release).isEmpty)
    }

    @Test func administratorPathAndRelaunchFailure() async throws {
        NetworkStub.reset()
        let release = try makeRelease("admin")
        defer { try? FileManager.default.removeItem(at: release.root) }
        serve(release)
        // 2026-11-20 오너 결정(A): 기본으로 꺼져 있다 — 내려받기 전에 알리고 아무것도 받지 않는다.
        let off = harness(release)
        off.strategy = .adminPrompt
        let disabled = off.make()
        await disabled.checkNow()
        await disabled.installAvailableUpdate()
        #expect(disabled.lastError == .administratorInstallDisabled && off.adminScripts.isEmpty)
        #expect(NetworkStub.count(ReleaseJSON.assetPath("1.1")) == 0, "nothing downloaded")
        if case .available = disabled.phase {} else { Issue.record("the update stays available (the release page link is still useful)") }

        let h = harness(release)
        h.strategy = .adminPrompt
        h.adminError = OnePercentError.cancelled
        var allowed = Fixture.configuration()
        allowed.allowsAdministratorInstall = true
        let updater = h.make(allowed)
        await updater.checkNow()
        await updater.installAvailableUpdate()
        #expect(updater.lastError == .cancelled, "the user closed the password prompt")
        let script = try #require(h.adminScripts.first)
        #expect(script.destination.path == release.installed.path)
        #expect(script.staging.path.hasPrefix("/private/tmp/OnePercent-com.example.testapp-"))
        #expect(script.backup.deletingLastPathComponent().path == release.installed.deletingLastPathComponent().path)
        #expect(script.identity == VerifiedIdentity(bundleID: Fixture.bundleID, version: "1.1", build: "2"))
        #expect(script.requirement == UpdateDecision.codeRequirement(bundleIdentifier: Fixture.bundleID, team: Fixture.team))

        let relaunch = harness(release)
        relaunch.relaunchError = OnePercentError.relaunchFailed("test")
        let second = relaunch.make()
        await second.checkNow()
        await second.installAvailableUpdate()
        #expect(second.lastError == .relaunchFailed("test"))
        #expect(Fixture.marker(release.installed) == "new" && second.phase == .idle, "installed; no second install offered")
        #expect(!second.presentation.showsInstallButton, "2026-11-20 리뷰 P2-5a: the button does not come back either")
    }

    // MARK: - PR #1 code review follow-ups (2026-11-20)

    /// P1-2: after a relaunch only the stored latest version is known — Install asks GitHub again first, then installs.
    @Test func installAfterRelaunchAsksAgainFirst() async throws {
        NetworkStub.reset()
        let release = try makeRelease("recheck")
        defer { try? FileManager.default.removeItem(at: release.root) }
        serve(release)
        let h = harness(release)
        await h.make().checkNow(userInitiated: false)          // found 1.1, the user said "later"
        let updater = h.make()                                  // next launch
        #expect(updater.phase == .idle && updater.presentation.showsInstallButton && updater.presentation.installRechecksFirst)
        let before = apiCount
        await updater.installAvailableUpdate()
        #expect(apiCount == before + 1, "asked again first")
        #expect(Fixture.marker(release.installed) == "new" && h.relaunched.count == 1 && updater.lastError == nil)

        // The release was withdrawn meanwhile: nothing is installed, and the button goes away.
        let goneRelease = try makeRelease("recheck-gone")
        defer { try? FileManager.default.removeItem(at: goneRelease.root) }
        let gone = harness(goneRelease)
        gone.store.set("1.1", forKey: keys.latestVersion)
        respond("1.0")
        let stale = gone.make()
        await stale.installAvailableUpdate()
        #expect(stale.phase == .upToDate && gone.relaunched.isEmpty && !stale.presentation.showsInstallButton)
    }

    /// P2-3: cancel during verification stops before the remaining checks.
    @Test func cancelDuringVerification() async throws {
        NetworkStub.reset()
        let release = try makeRelease("cancel-verify")
        defer { try? FileManager.default.removeItem(at: release.root) }
        serve(release)
        let h = harness(release)
        let log = CallLog()
        h.checks = BundleChecks(signedByTeam: { _, _ in log.add("team"); Thread.sleep(forTimeInterval: 0.5); return true },
                                codesignValid: { _, _ in log.add("codesign"); return true },
                                notarizationAccepted: { _ in log.add("spctl"); return true })
        let updater = h.make()
        await updater.checkNow()
        let install = Task { await updater.installAvailableUpdate() }
        await waitUntil("team check") { log.all.contains("team") }
        #expect(updater.phase == .verifying && updater.presentation.showsCancelButton)
        updater.cancel()
        await install.value
        #expect(updater.lastError == .cancelled)
        #expect(log.all == ["team"], "codesign and spctl never ran: \(log.all)")
        #expect(Fixture.marker(release.installed) == "old" && leftovers(release).isEmpty)
        if case .available = updater.phase {} else { Issue.record("still available after cancel") }
    }

    /// P2-7: once an install has started, suspend() is refused — even before the phase changes.
    @Test func suspendIsRefusedOnceInstallStarts() async throws {
        NetworkStub.reset()
        let release = try makeRelease("suspend-install")
        defer { try? FileManager.default.removeItem(at: release.root) }
        serve(release)
        let h = harness(release)
        let updater = h.make()
        await updater.checkNow()
        var duringGuard: Bool?
        updater.installGuard = {
            if duringGuard == nil { duringGuard = updater.suspend() }   // the phase is still .available here
            return nil
        }
        await updater.installAvailableUpdate()
        #expect(duringGuard == false)
        #expect(Fixture.marker(release.installed) == "new")
    }

    /// P2-8: resume() without suspend() leaves a running check alone.
    @Test func resumeWithoutSuspendChangesNothing() async {
        NetworkStub.reset()
        let h = Harness()
        let updater = h.make()
        NetworkStub.set(ReleaseJSON.apiPath, .init(body: ReleaseJSON.body(tag: "1.1"), holdAfterChunks: 0))
        let check = Task { await updater.checkNow() }
        await waitUntil { NetworkStub.isHolding }
        updater.resume()
        NetworkStub.release()
        await check.value
        if case .available = updater.phase {} else { Issue.record("stuck: \(updater.phase)") }
    }

    /// P2-5b: the app refused to quit after the new version opened.
    @Test func appRefusingToQuit() async throws {
        NetworkStub.reset()
        let release = try makeRelease("quit-refused")
        defer { try? FileManager.default.removeItem(at: release.root) }
        serve(release)
        let h = harness(release)
        h.relaunchError = OnePercentError.quitCancelled
        let updater = h.make()
        await updater.checkNow()
        await updater.installAvailableUpdate()
        #expect(updater.lastError == .quitCancelled && updater.phase == .idle && updater.installedThisRun == "1.1")
        #expect(Fixture.marker(release.installed) == "new" && !updater.presentation.showsInstallButton)
        await updater.checkNow()
        #expect(updater.phase == .upToDate, "1.1 counts as installed in this run")
        #expect(updater.suspend(), "nothing is running any more")
    }

    /// P3-10: stopping right after starting cancels the delayed first check.
    @Test func stoppingCancelsTheFirstCheck() async throws {
        NetworkStub.reset()
        let h = Harness()
        h.firstCheckDelay = .milliseconds(50)
        respond("1.1")
        let updater = h.make()
        updater.startAutomaticChecks()
        updater.stopAutomaticChecks()
        try await Task.sleep(for: .milliseconds(300))
        #expect(apiCount == 0 && h.notices.isEmpty)
        updater.startAutomaticChecks()
        await waitUntil("first check") { h.notices == ["1.1"] }
        updater.stopAutomaticChecks()
    }

    /// 2026-11-20 (보안 리뷰 P3-6): 시험 저장소는 앱 코드로만 켠다(UserDefaults 키는 더 없다).
    @Test func testRepositoryComesFromCode() {
        var config = Fixture.configuration()
        #expect(Harness().make(config).repository == "owner/TestApp")
        config.testRepository = "owner/TestAppStaging"
        #expect(Harness().make(config).repository == "owner/TestAppStaging", "debug build of the package")
        config.testRepository = "bad/../repo"
        #expect(!config.problems.isEmpty)
        let h = Harness()
        h.store.set(true, forKey: "OnePercent.allowTestRepository")
        h.store.set("evil/repo", forKey: "OnePercent.testRepository")
        #expect(h.make().repository == "owner/TestApp", "old defaults keys do nothing")
    }

    @Test func secondNoteLaunchAndBadVersion() {
        let h = Harness()
        h.version = "1.1"
        h.store.set("1.0", forKey: keys.lastLaunchedVersion)
        let updater = h.make()
        #expect(updater.noteLaunch() == "1.1")
        #expect(updater.noteLaunch() == "1.1" && updater.justUpdatedTo == "1.1", "a second call does not clear it")
        let beta = Harness()
        beta.version = "1.0-beta"
        let broken = beta.make()
        #expect(broken.noteLaunch() == nil && broken.lastError?.code == "badConfiguration", "a running version the scheme cannot read is reported")
    }
}
