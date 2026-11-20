import AppKit
import Foundation
import Observation

/// Where OnePercent keeps its few values. `UserDefaults` already conforms; tests use an in-memory store.
public protocol OnePercentStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: OnePercentStore {}

/// Checks GitHub for a newer release, tells the user, and — only when the user asks — downloads, verifies and installs it,
/// then reopens the app.
///
/// Security boundary: **this replaces your app with a file from the internet.** So:
/// - Nothing touches the installed app before every check passes: archive listing and limits, a real folder, the bundle ID,
///   your Team's Apple-issued signature (Security.framework and `codesign --deep --strict`), notarization (`spctl`),
///   a higher version and build, and the exact version that was announced.
/// - The old app is never deleted first. The new one is staged next to it and swapped in one step, or (administrator path)
///   moved aside as a backup that is restored if placing the new one fails.
/// - Tools run with argument arrays. The single shell command (administrator path) quotes every path.
/// - HTTPS only; redirects only within ``OnePercentConfiguration/allowedHosts``.
/// - Requests carry only `Accept`, `User-Agent` and a fixed `Accept-Language: en` (so the user's language list is not sent).
/// - Background checks only announce. Installing always needs ``installAvailableUpdate()``.
///
/// Your app must not refuse to quit (`applicationShouldTerminate` returning `.terminateCancel`) while an update reopens it.
///
/// 2026-11-20: 하늘키보드 `Updater`(2026-09-21 #19 — Sparkle 대신 직접 구현, 흐름은 exelban/stats 참고·코드는 새로 씀)를
/// 설정·버전 규칙·문구·위치 정책을 바꿔 끼울 수 있게 일반화했다. Fable 리뷰로 고친 것: 실패가 "새 버전 있음"을 덮어쓰지 않음,
/// 설치 파일 없는 새 태그는 확인 시각을 남기지 않음(다음 정시에 다시 확인), 내려받기 진행률·취소, 남은 staging 정리.
/// 2026-11-20 (PR #1 코드 리뷰, Fable 5.2): 재실행 뒤 설치 버튼이 스스로 다시 확인 · 검증 중 취소 · 설치 파일 없는 태그를
/// 최신 번호로 저장하지 않음 · 재실행 실패·종료 거부 뒤 상태 · 빌드 번호 판정 분리 · 설치 시작 틈의 suspend · 짝 없는 resume ·
/// 첫 확인 취소 · 일정 여유 · 두 번째 noteLaunch.
@MainActor
@Observable
public final class OnePercentUpdater {
    public enum Phase: Equatable, Sendable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case downloading(fraction: Double?)
        case verifying
        case installing
    }

    public private(set) var phase: Phase = .idle
    /// The most recent failure. Cleared when a new check or install starts. A failure never hides a known update.
    public private(set) var lastError: OnePercentError?
    /// The last time GitHub was asked **successfully**. Failed attempts do not move it, so the next hourly tick tries again.
    public private(set) var lastCheck: Date?
    public private(set) var automaticChecksEnabled: Bool
    /// The newest installable version seen on GitHub (stored across launches). A tag whose ZIP is missing does not count.
    public private(set) var latestVersion: String?
    /// Set by ``noteLaunch()`` when this launch is the first one after an update: the new version.
    public private(set) var justUpdatedTo: String?
    /// Set when this run already put a new version in place but did not reopen (it is installed; the running copy is old).
    public private(set) var installedThisRun: String?

    public let configuration: OnePercentConfiguration

    /// Called when a check finds a new version that should be announced (automatic checks announce each version once).
    /// Show your own notice here. Installing does not start from this callback.
    @ObservationIgnored public var onUpdateAvailable: (@MainActor (AvailableUpdate) -> Void)?
    /// Asked right before downloading and again right before replacing. Return a short, localized reason to refuse
    /// (for example "A timer is running.") or `nil` to allow.
    @ObservationIgnored public var installGuard: (@MainActor () -> String?)?
    /// Called after the new app is in place, right before the app reopens. **Save state here** — the new copy starts
    /// before this one's `applicationWillTerminate` runs.
    @ObservationIgnored public var willRelaunch: (@MainActor () -> Void)?

    @ObservationIgnored private let store: OnePercentStore
    @ObservationIgnored private let sessionConfiguration: URLSessionConfiguration
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let gate: OperationGate
    @ObservationIgnored private let environment: Environment
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var firstCheck: Task<Void, Never>?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var installing = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var responseEpoch = 0
    @ObservationIgnored private var wasScheduled = false
    @ObservationIgnored private var launchNoted = false
    @ObservationIgnored private var lastNotifiedVersion: String?
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var lastReportedFraction: Double = -1

    /// - Parameters:
    ///   - configuration: Your app's release settings.
    ///   - defaults: Where to keep the stored values. Default: `UserDefaults.standard`.
    ///   - gate: Share one gate with your own long operations so they never overlap with an update.
    public convenience init(configuration: OnePercentConfiguration, defaults: OnePercentStore = UserDefaults.standard,
                            gate: OperationGate? = nil) {
        self.init(configuration: configuration, store: defaults, session: nil, now: Date.init, gate: gate, environment: .live)
    }

    init(configuration: OnePercentConfiguration, store: OnePercentStore, session: URLSession?, now: @escaping () -> Date,
         gate: OperationGate?, environment: Environment) {
        self.configuration = configuration
        self.store = store
        self.now = now
        self.gate = gate ?? OperationGate()
        self.environment = environment
        let keys = Keys(configuration.defaultsKeyPrefix)
        automaticChecksEnabled = store.object(forKey: keys.automaticChecks) as? Bool ?? configuration.automaticChecksByDefault
        lastCheck = store.object(forKey: keys.lastCheck) as? Date
        latestVersion = (store.object(forKey: keys.latestVersion) as? String).flatMap { configuration.versionScheme.isValid($0) ? $0 : nil }
        lastNotifiedVersion = store.object(forKey: keys.lastNotifiedVersion) as? String
        sessionConfiguration = session?.configuration ?? Self.sessionConfiguration()
    }

    /// Request settings: no disk cache, no cookies. 30 s without data ends a request; a whole download may take an hour.
    /// 2026-11-20 (리뷰 P3-13): 전체 제한 10분은 500 MiB 기본 상한과 맞지 않았다(느린 회선에서 항상 실패).
    nonisolated static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60 * 60
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        return config
    }

    // MARK: - Stored values

    struct Keys {
        let automaticChecks, lastCheck, latestVersion, lastNotifiedVersion, lastLaunchedVersion: String
        init(_ prefix: String) {
            automaticChecks = prefix + "automaticChecks"
            lastCheck = prefix + "lastCheck"
            latestVersion = prefix + "latestVersion"
            lastNotifiedVersion = prefix + "lastNotifiedVersion"
            lastLaunchedVersion = prefix + "lastLaunchedVersion"
        }
        var all: [String] { [automaticChecks, lastCheck, latestVersion, lastNotifiedVersion, lastLaunchedVersion] }
    }

    private var keys: Keys { Keys(configuration.defaultsKeyPrefix) }

    /// Every key OnePercent may write. Remove them when your app resets itself.
    public nonisolated static func storedKeys(configuration: OnePercentConfiguration) -> [String] {
        Keys(configuration.defaultsKeyPrefix).all
    }

    /// Prefix of the work folders in the temporary directory (followed by a UUID).
    var workPrefix: String { "OnePercent-\(configuration.bundleIdentifier)-" }

    /// Removes what an interrupted update left behind — the hidden staging copy next to the app and the work folders in
    /// the temporary directory. Only this app's items (by name, ending in a UUID), owned by this user, never links.
    /// ``noteLaunch()`` already does this at launch for items older than ten minutes; call this from your app's own
    /// "remove the app" feature with `olderThan: 0`. Returns how many items were removed.
    /// 2026-11-20: PomoLight 의 삭제 기능이 앱을 휴지통으로 옮길 때 옆에 남은 숨은 사본까지 치우려고 공개했다.
    @discardableResult
    public nonisolated static func removeLeftovers(configuration: OnePercentConfiguration,
                                                   installedApp: URL = Bundle.main.bundleURL,
                                                   olderThan minimumAge: TimeInterval = 10 * 60) -> Int {
        UpdateReplacement.removeLeftovers(installedApp: installedApp,
                                          workPrefix: "OnePercent-\(configuration.bundleIdentifier)-",
                                          olderThan: minimumAge)
    }

    // MARK: - Versions

    /// The running app's public version (`CFBundleShortVersionString` plus the optional suffix key).
    public var currentVersion: String { environment.currentVersion(configuration) }

    /// The repository being checked: ``OnePercentConfiguration/testRepository`` in debug builds when the app set it, otherwise
    /// ``OnePercentConfiguration/repository``.
    var repository: String {
        #if DEBUG
        if let test = configuration.testRepository, OnePercentConfiguration.isValidRepository(test) { return test }
        #endif
        return configuration.repository
    }

    /// The configuration with ``repository`` filled in — what releases are matched against.
    private var effectiveConfiguration: OnePercentConfiguration {
        var effective = configuration
        effective.repository = repository
        return effective
    }

    /// The release page for a version (for "What's new" after an update).
    public func releasePageURL(forVersion version: String) -> URL? {
        ReleaseDecision.releasePageURL(tag: configuration.tagPrefix + version, configuration: effectiveConfiguration)
    }

    /// The installed version as far as updates are concerned: what this run put in place, or the running version.
    private var effectiveInstalledVersion: String { installedThisRun ?? currentVersion }

    private var storedLatestIsNewer: Bool {
        latestVersion.map { configuration.versionScheme.isNewer($0, than: effectiveInstalledVersion) } ?? false
    }

    public var presentation: UpdateStatusPresentation {
        .resolve(phase: phase, error: lastError, storedLatestIsNewer: storedLatestIsNewer)
    }

    // MARK: - Settings

    public func setAutomaticChecksEnabled(_ enabled: Bool) {
        guard !suspended else { return }
        automaticChecksEnabled = enabled
        store.set(enabled, forKey: keys.automaticChecks)
    }

    /// Call once at launch. Records the running version, reports whether this launch follows an update, and removes
    /// leftovers of an interrupted update. Returns the new version when this launch follows an update.
    /// Calling it again in the same run returns the same answer without recording anything.
    @discardableResult
    public func noteLaunch() -> String? {
        guard !suspended else { return nil }
        guard !launchNoted else { return justUpdatedTo }
        launchNoted = true
        let current = currentVersion
        // 2026-11-20 (리뷰 P3-11): 실행 중인 버전을 규칙이 못 읽으면 어떤 릴리스도 새것이 아니다 — 조용히 넘기지 않고 알린다.
        guard configuration.versionScheme.isValid(current) else {
            lastError = .badConfiguration("the running version \"\(current)\" is not a \(configuration.versionScheme.name) version")
            return nil
        }
        let updated = UpdateDecision.justUpdatedVersion(current: current, lastLaunched: store.object(forKey: keys.lastLaunchedVersion) as? String,
                                                        configuration: configuration)
        store.set(current, forKey: keys.lastLaunchedVersion)
        justUpdatedTo = updated
        let installed = environment.runningBundleURL()
        let prefix = workPrefix
        let temporary = environment.temporaryDirectory
        Task.detached(priority: .utility) {
            let removed = UpdateReplacement.removeLeftovers(installedApp: installed, workPrefix: prefix, temporaryDirectory: temporary)
            if removed > 0 { onePercentLog.notice("removed \(removed) leftover update item(s)") }
        }
        return updated
    }

    // MARK: - Background checks

    /// Checks shortly after launch and then every hour whether a check is due (by ``OnePercentConfiguration/schedule``).
    /// An hourly tick instead of one long timer catches up within an hour after sleep or a failed attempt.
    public func startAutomaticChecks() {
        guard timer == nil, !suspended else { return }
        wasScheduled = true
        firstCheck = Task { [weak self] in
            try? await Task.sleep(for: self?.environment.firstCheckDelay ?? .seconds(15))
            guard !Task.isCancelled else { return }
            await self?.checkNow(userInitiated: false)
        }
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkNow(userInitiated: false) }
        }
        timer.tolerance = 5 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopAutomaticChecks() {
        timer?.invalidate()
        timer = nil
        firstCheck?.cancel()
        firstCheck = nil
        wasScheduled = false
    }

    /// Pauses all checking and writing — for example while your app removes its own data. Late responses are ignored.
    /// Returns `false` (and does nothing) while an install is starting or running.
    public func suspend() -> Bool {
        // 2026-11-20 (리뷰 P2-7): 설치를 시작한 직후(아직 phase 가 .available)에도 거절한다.
        guard !installing else { return false }
        switch phase { case .downloading, .verifying, .installing: return false; default: break }
        suspended = true
        responseEpoch += 1
        timer?.invalidate()
        timer = nil
        firstCheck?.cancel()
        firstCheck = nil
        if phase == .checking { phase = .idle }
        return true
    }

    /// Ends a ``suspend()``. Does nothing when not suspended.
    public func resume() {
        // 2026-11-20 (리뷰 P2-8): 짝 없는 resume 이 진행 중인 확인의 응답을 버려 .checking 에 멈췄다.
        guard suspended else { return }
        suspended = false
        responseEpoch += 1
        if wasScheduled { startAutomaticChecks() }
    }

    // MARK: - Check

    /// Asks GitHub for the latest release and updates ``phase``.
    /// - Parameters:
    ///   - userInitiated: The user asked — ignore the switch and the schedule.
    ///   - showNotice: Call ``onUpdateAvailable`` for a found update. Pass `false` when the result is shown in place
    ///     (a settings screen); the version then also counts as announced so no popup repeats it later.
    public func checkNow(userInitiated: Bool = true, showNotice: Bool = true) async {
        guard !busy, !suspended, gate.operation == nil, UpdateDecision.shouldCheckNow(
            schedule: configuration.schedule, automaticChecksEnabled: automaticChecksEnabled,
            lastCheck: lastCheck, now: now(), forced: userInitiated) else { return }
        guard configuration.problems.isEmpty else {
            lastError = .badConfiguration(configuration.problems.joined(separator: "; "))
            return
        }
        busy = true
        defer { busy = false }
        let known: AvailableUpdate? = if case .available(let update) = phase { update } else { nil }
        let restore: Phase = known.map(Phase.available) ?? .idle
        phase = .checking
        lastError = nil
        let epoch = responseEpoch
        do {
            let release = try await fetchLatestRelease()
            guard epoch == responseEpoch, !suspended else {
                if phase == .checking { phase = restore }
                return
            }
            guard let releaseVersion = ReleaseDecision.version(fromTag: release.tag, configuration: configuration) else {
                // 2026-11-20 (리뷰 P3-11): 태그 꼴이 설정과 안 맞는 건 서버 고장이 아니라 설정 문제다.
                throw OnePercentError.badConfiguration("tag \"\(release.tag)\" is not a \(configuration.versionScheme.name) version "
                                                       + "with tag prefix \"\(configuration.tagPrefix)\"")
            }
            let installed = effectiveInstalledVersion
            if let update = ReleaseDecision.availableUpdate(currentVersion: installed, release: release, configuration: effectiveConfiguration) {
                recordSuccessfulCheck(latest: releaseVersion)
                phase = .available(update)
                onePercentLog.notice("update available: \(update.tag, privacy: .public) (installed \(installed, privacy: .public))")
                announce(update, userInitiated: userInitiated, showNotice: showNotice)
            } else if configuration.versionScheme.isNewer(releaseVersion, than: installed) {
                // 2026-11-20 (Fable 리뷰): 새 태그는 있는데 받을 파일이 아직 없다. 확인 시각을 남기면 다음 주기(최대 한 달)까지 다시 묻지 않으므로
                // 남기지 않는다 — 다음 정시 틱에 다시 확인한다.
                // 2026-11-20 (PR #1 리뷰 P2-4): 최신 번호로도 저장하지 않는다. 저장하면 설치할 수 없는 버전의 설치 버튼이 재실행 뒤에도 남았다.
                phase = restore
                lastError = .assetNotReady(releaseVersion)
            } else {
                recordSuccessfulCheck(latest: releaseVersion)
                phase = .upToDate
            }
        } catch {
            guard epoch == responseEpoch, !suspended else {
                if phase == .checking { phase = restore }
                return
            }
            phase = restore
            lastError = Self.describe(error)
            onePercentLog.error("check failed: \(self.lastError?.code ?? "?", privacy: .public)")
        }
    }

    private func recordSuccessfulCheck(latest: String) {
        let checkedAt = now()
        lastCheck = checkedAt
        store.set(checkedAt, forKey: keys.lastCheck)
        latestVersion = latest
        store.set(latest, forKey: keys.latestVersion)
    }

    private func announce(_ update: AvailableUpdate, userInitiated: Bool, showNotice: Bool) {
        let alreadyNotified = lastNotifiedVersion.map { configuration.versionScheme.isSame($0, update.version) } ?? false
        if !showNotice {
            markNotified(update.version)
        } else if (userInitiated || automaticChecksEnabled), (userInitiated || !alreadyNotified), let onUpdateAvailable {
            // 조회 중에 스위치를 끈 경우에도 응답 시점의 설정을 지킨다. 알림 창이 연결되지 않았으면 알렸다고 기록하지 않는다.
            markNotified(update.version)
            onUpdateAvailable(update)
        }
    }

    private func markNotified(_ version: String) {
        lastNotifiedVersion = version
        store.set(version, forKey: keys.lastNotifiedVersion)
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        let repository = repository
        guard let url = ReleaseDecision.latestReleaseURL(repository: repository) else { throw OnePercentError.badConfiguration("repository") }
        let received = try await UpdateTransport.receive(request(for: url), configuration: sessionConfiguration,
                                                         limit: configuration.limits.maxMetadataBytes,
                                                         allowedHosts: configuration.allowedHosts)
        let http = received.response
        switch http.statusCode {
        case 200:
            guard let release = ReleaseDecision.parseRelease(received.data, allowedHosts: configuration.allowedHosts) else {
                throw OnePercentError.malformedResponse
            }
            return release
        case 300...399: throw OnePercentError.redirectBlocked(ReleaseDecision.display(http.value(forHTTPHeaderField: "Location")))
        case 404: throw OnePercentError.noRelease(repository)
        case 403, 429: throw OnePercentError.rateLimited
        default: throw OnePercentError.httpStatus(http.statusCode)
        }
    }

    /// The headers OnePercent sets: `Accept`, `User-Agent`, and a fixed `Accept-Language: en`
    /// (setting it stops URLSession from sending the user's language list — 2026-11-13 하늘키보드 실측).
    func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.userAgent ?? "\(configuration.appName)/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    // MARK: - Install

    /// Downloads, verifies and installs the available update, then reopens the app.
    /// After a relaunch only the stored latest version is known (``UpdateStatusPresentation/installRechecksFirst``);
    /// this then asks GitHub again first and continues if the update is still there.
    /// On failure the update stays available and ``lastError`` says why. If even restoring the old app failed, the error
    /// names the backup and where it belongs.
    public func installAvailableUpdate() async {
        // 2026-11-20 (리뷰 P1-2): 다시 켠 뒤 보이는 설치 버튼이 아무 일도 하지 않았다. 여기서 스스로 다시 확인한다.
        if phase == .idle, storedLatestIsNewer, !busy, !suspended {
            await checkNow(userInitiated: true, showNotice: false)
        }
        guard case .available(let update) = phase, !busy, !suspended, !installing else { return }
        // 2026-11-20 (리뷰 P2-7): 맨 처음부터 "설치 중"으로 표시해, 시작 직후의 suspend() 를 거절한다.
        installing = true
        defer { installing = false }
        if let reason = installGuard?() { lastError = .blocked(reason); return }
        guard configuration.problems.isEmpty else {
            lastError = .badConfiguration(configuration.problems.joined(separator: "; "))
            return
        }
        guard let token = gate.begin("OnePercent.update") else { lastError = .busy; return }
        busy = true
        defer { busy = false; gate.finish(token) }
        lastError = nil
        let task = Task { await self.performInstall(update) }
        installTask = task
        await task.value
        installTask = nil
    }

    /// Stops a download or verification in progress. Once replacing has begun it cannot be cancelled.
    public func cancel() {
        switch phase {
        case .downloading, .verifying: installTask?.cancel()
        default: break
        }
    }

    private func performInstall(_ update: AvailableUpdate) async {
        let fm = FileManager.default
        let running = environment.runningBundleURL()
        let readOnly = (try? running.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        let target: URL
        switch UpdateDecision.installTarget(runningBundlePath: running.path, configuration: configuration, isReadOnlyVolume: readOnly,
                                            applicationsDirectory: environment.applicationsDirectory) {
        case .failure(let error):
            lastError = error
            return
        case .success(let path):
            target = URL(fileURLWithPath: path)
        }
        // 2026-11-20 오너 결정(A): 관리자 경로가 꺼져 있으면 내려받기 전에 알린다(받아 놓고 못 쓰지 않게).
        if environment.strategy(target) == .adminPrompt, !configuration.allowsAdministratorInstall {
            lastError = .administratorInstallDisabled
            return
        }
        let workDir = environment.temporaryDirectory.appendingPathComponent(workPrefix + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: workDir) }
        var placed = false
        do {
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
            lastReportedFraction = -1
            phase = .downloading(fraction: nil)
            let zip = workDir.appendingPathComponent("update.zip")
            try await download(update.asset, to: zip)
            try Task.checkCancellation()

            phase = .verifying
            let input = UpdateVerifier.Input(zip: zip, workDir: workDir, configuration: configuration,
                                             currentVersion: currentVersion, currentBuild: environment.currentBuild(),
                                             releaseVersion: update.version)
            let checks = environment.checks
            // 2026-11-20 (리뷰 P2-3): detached 작업은 부모의 취소를 물려받지 않는다 — 취소를 직접 넘긴다.
            // 검증 쪽은 풀기 감시 루프와 검사 사이에서 취소를 본다.
            let verification = Task.detached(priority: .userInitiated) { try UpdateVerifier.extractAndVerify(input, checks: checks) }
            let verified = try await withTaskCancellationHandler { try await verification.value } onCancel: { verification.cancel() }
            try Task.checkCancellation()
            onePercentLog.notice("update \(update.tag, privacy: .public) verified")
            // 내려받는 동안 앱 상태가 바뀌었을 수 있다(예: 타이머 시작). 바꾸기 직전에 한 번 더 묻는다.
            if let reason = installGuard?() { throw OnePercentError.blocked(reason) }

            phase = .installing
            let requirement = UpdateDecision.codeRequirement(bundleIdentifier: configuration.bundleIdentifier, team: configuration.teamIdentifier)
            switch environment.strategy(target) {
            case .adminPrompt where !configuration.allowsAdministratorInstall:
                throw OnePercentError.administratorInstallDisabled
            case .userAtomic:
                let verifyCopy = environment.verifyCopy
                try await Task.detached(priority: .userInitiated) {
                    try UpdateReplacement.replaceAtomically(destination: target, with: verified, requirement: requirement, verifyCopy: verifyCopy)
                }.value
            case .adminPrompt:
                let token = UUID().uuidString
                let script = AdminReplacementScript(
                    source: verified.app, destination: target,
                    staging: AdminReplacementScript.privateStaging(bundleID: configuration.bundleIdentifier, token: token),
                    backup: target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).old-\(token)"),
                    identity: verified.identity, requirement: requirement)
                if let notice = try environment.adminReplace(script), !notice.isEmpty {
                    onePercentLog.notice("administrator replacement: \(notice, privacy: .private)")
                }
            }
            placed = true
            onePercentLog.notice("update \(update.tag, privacy: .public) installed — reopening")
            // 재실행은 앱을 끝내므로 defer 가 돌지 않는다. 먼저 지운다(2026-11-07 하늘키보드 #176 F-7).
            try? fm.removeItem(at: workDir)
            willRelaunch?()
            try await environment.relaunch(target)
        } catch {
            let described = Self.describe(error)
            if placed {
                // 2026-11-20 (리뷰 P2-5): 새 앱은 이미 제자리에 있다(다시 열지 못했거나, 앱이 종료를 거부했다).
                // 같은 버전을 또 설치하라고 권하지 않도록 이 실행에서 설치한 버전을 기억한다.
                installedThisRun = update.version
                phase = .idle
            } else {
                phase = .available(update)
            }
            lastError = described
            onePercentLog.error("install failed: \(described.code, privacy: .public)")
        }
    }

    private func download(_ asset: ReleaseAsset, to destination: URL) async throws {
        // 2026-11-20 (리뷰 P3-14): 1% 걸러내기를 전송 쪽에서 해 청크마다 메인 액터 작업을 만들지 않는다.
        // Content-Length 가 없으면 API 의 자산 크기를 쓴다.
        let throttle = ProgressThrottle(fallbackTotal: asset.size > 0 ? Int64(asset.size) : nil)
        let progress: UpdateTransport.Progress = { [weak self] received, expected in
            guard let fraction = throttle.next(received: received, expected: expected) else { return }
            Task { @MainActor [weak self] in self?.reportProgress(fraction) }
        }
        let received = try await UpdateTransport.receive(request(for: asset.downloadURL), configuration: sessionConfiguration,
                                                         limit: configuration.limits.maxAssetBytes,
                                                         allowedHosts: configuration.allowedHosts,
                                                         destination: destination, progress: progress)
        let http = received.response
        guard http.statusCode == 200 else {
            if (300...399).contains(http.statusCode) {
                throw OnePercentError.redirectBlocked(ReleaseDecision.display(http.value(forHTTPHeaderField: "Location")))
            }
            throw OnePercentError.httpStatus(http.statusCode)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? Int ?? 0
        guard size > 0, size <= configuration.limits.maxAssetBytes else { throw OnePercentError.badSize(size) }
        if asset.size > 0, asset.size != size { throw OnePercentError.sizeMismatch(expected: asset.size, actual: size) }
        // 2026-11-20 (리서치 P9): GitHub 가 지문을 주면 받으면서 잰 값과 대조한다. 안 주면(옛 릴리스) 크기와 코드 서명으로만 본다.
        if let expected = asset.sha256, received.sha256 != expected { throw OnePercentError.digestMismatch }
    }

    private func reportProgress(_ fraction: Double) {
        guard case .downloading = phase else { return }
        let clamped = min(max(fraction, 0), 1)
        guard clamped > lastReportedFraction else { return }
        lastReportedFraction = clamped
        phase = .downloading(fraction: clamped)
    }

    static func describe(_ error: Error) -> OnePercentError {
        if let error = error as? OnePercentError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError { return error.code == .cancelled ? .cancelled : .network(error.localizedDescription) }
        // 2026-11-20 (리뷰 P3-12): 디스크 가득 참·폴더 만들기 실패 같은 파일 오류를 "네트워크 오류"로 부르지 않는다.
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain || nsError.domain == NSPOSIXErrorDomain { return .fileSystem(nsError.localizedDescription) }
        return .network(error.localizedDescription)
    }
}

/// Forwards download progress only when it moved by at least 1 %. Thread-safe; called on the transfer queue.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last: Double = -1
    private let fallbackTotal: Int64?

    init(fallbackTotal: Int64?) { self.fallbackTotal = fallbackTotal }

    func next(received: Int64, expected: Int64?) -> Double? {
        guard let total = expected ?? fallbackTotal, total > 0 else { return nil }
        let fraction = min(Double(received) / Double(total), 1)
        return lock.withLock {
            guard fraction - last >= 0.01 || (fraction == 1 && last < 1) else { return nil }
            last = fraction
            return fraction
        }
    }
}

// MARK: - Environment (swapped in tests)

extension OnePercentUpdater {
    struct Environment {
        var currentVersion: @MainActor (OnePercentConfiguration) -> String
        var currentBuild: @MainActor () -> String?
        var runningBundleURL: @MainActor () -> URL
        var applicationsDirectory: String
        var temporaryDirectory: URL
        var checks: BundleChecks
        var strategy: @MainActor (URL) -> UpdateDecision.ReplaceStrategy
        var verifyCopy: (@Sendable (URL, VerifiedIdentity) -> Bool)?
        var adminReplace: @MainActor (AdminReplacementScript) throws -> String?
        var relaunch: @MainActor (URL) async throws -> Void
        /// The wait before the first background check after ``OnePercentUpdater/startAutomaticChecks()``.
        var firstCheckDelay: Duration = .seconds(15)

        static var live: Environment {
            Environment(
                currentVersion: { configuration in
                    let info = Bundle.main.infoDictionary
                    return UpdateDecision.bundleVersion(info: info, configuration: configuration)
                        ?? (info?["CFBundleShortVersionString"] as? String) ?? "0"
                },
                currentBuild: { Bundle.main.infoDictionary?["CFBundleVersion"] as? String },
                runningBundleURL: { Bundle.main.bundleURL },
                applicationsDirectory: "/Applications",
                temporaryDirectory: FileManager.default.temporaryDirectory,
                checks: .live,
                strategy: { UpdateReplacement.strategy(for: $0) },
                verifyCopy: nil,
                adminReplace: { script in
                    // NSAppleScript 의 관리자 인증 창은 메인 스레드에서 띄운다. 인증 뒤 복사·서명 확인 동안 메인 스레드가 멈춘다
                    // (Fable 리뷰 — 알려진 한계. 하늘키보드도 같다).
                    var errorInfo: NSDictionary?
                    guard let appleScript = NSAppleScript(source: script.appleScriptSource) else {
                        throw OnePercentError.replaceFailed("AppleScript")
                    }
                    let result = appleScript.executeAndReturnError(&errorInfo)
                    if let errorInfo {
                        let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 1
                        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? ""
                        if number == -128 { throw OnePercentError.cancelled }   // 사용자가 인증 창에서 취소
                        throw script.error(status: number, message: message)
                    }
                    return result.stringValue
                },
                relaunch: { url in
                    // 하늘키보드와 같은 방식: 바뀐 번들을 새 인스턴스로 열고, 열렸을 때만 지금 앱을 끝낸다(설명 없이 사라지지 않게).
                    let config = NSWorkspace.OpenConfiguration()
                    config.createsNewApplicationInstance = true
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                            if let error { continuation.resume(throwing: OnePercentError.relaunchFailed(error.localizedDescription)) }
                            else { continuation.resume() }
                        }
                    }
                    NSApp.terminate(nil)
                    // 2026-11-20 (리뷰 P2-5b): terminate 가 돌아왔다 = 앱이 종료를 거부했다. 새 앱은 이미 떠 있다.
                    throw OnePercentError.quitCancelled
                })
        }
    }
}
