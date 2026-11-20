import Foundation
import Security
import os

let onePercentLog = Logger(subsystem: "OnePercent", category: "update")

/// The downloaded app passed every check. Carries what was read at check time — the temporary copy may change
/// afterwards (same-user code can write there), so later steps compare against these values instead of re-reading.
struct VerifiedUpdate: Sendable {
    let app: URL
    let identity: VerifiedIdentity
}

/// Bundle ID, version and build read from the verified app.
struct VerifiedIdentity: Equatable, Sendable {
    let bundleID: String
    let version: String
    let build: String
}

/// The three checks that need a real Apple signature. Tests swap only these; everything else always runs for real.
/// 2026-11-13 (하늘키보드 #226 F-6): 예전엔 조립부가 시험에서 한 번도 실행되지 않았다. 이 셋만 바꿔 끼워 조립 순서를 실제로 돌린다.
struct BundleChecks: Sendable {
    var signedByTeam: @Sendable (_ app: URL, _ requirement: String) -> Bool
    var codesignValid: @Sendable (_ app: URL, _ requirement: String) -> Bool
    var notarizationAccepted: @Sendable (_ app: URL) -> Bool

    static let live = BundleChecks(
        signedByTeam: { BundleTrust.satisfies($0, requirement: $1) },
        codesignValid: { ProcessRunner.run("/usr/bin/codesign", UpdateDecision.codesignArguments(appPath: $0.path, requirement: $1)).status == 0 },
        notarizationAccepted: { ProcessRunner.run("/usr/sbin/spctl", ["-a", "-t", "exec", $0.path]).status == 0 })
}

/// Signature checks through Security.framework — independent of the `codesign` tool.
enum BundleTrust {
    /// The bundle's static code satisfies `requirement`, checking every architecture, strictly, including nested code,
    /// refusing symbolic links that leave the bundle and anything that is not app-like.
    /// 2026-11-20 (리서치 P1 — AppUpdater 와 같은 플래그): 링크 제한·앱 꼴 제한을 켰다. 실측(이 Mac): Ghostty·Firefox·Claude·MacWhisper 통과.
    static func satisfies(_ url: URL, requirement text: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: validityFlags), requirement) == errSecSuccess
    }

    static let validityFlags: UInt32 = UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSStrictValidate) | UInt32(kSecCSCheckNestedCode)
        | UInt32(kSecCSRestrictSymlinks) | UInt32(kSecCSRestrictToAppLike)

    /// The Team ID in a bundle's signature, if any. For diagnostics.
    static func teamIdentifier(at url: URL) -> String? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let fields = info as? [String: Any] else { return nil }
        return fields[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

/// Runs a tool with an argument array (never a shell string).
enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Listing check → guarded unpacking → checks → quarantine removal. Everything stays inside `workDir`.
enum UpdateVerifier {
    struct Input: Sendable {
        let zip: URL
        let workDir: URL
        let configuration: OnePercentConfiguration
        let currentVersion: String
        let currentBuild: String?
        /// The version the user was told about (the tag without its prefix).
        let releaseVersion: String
        /// Compare against the running version and build. Only the release checker turns this off when it has no previous release.
        var checkIncrease: Bool = true
    }

    static func extractAndVerify(_ input: Input, checks: BundleChecks = .live) throws -> VerifiedUpdate {
        let fm = FileManager.default
        let configuration = input.configuration
        let appFolder = configuration.appFolderName
        let limits = configuration.limits.archive
        try inspectArchive(input.zip, limits: limits, appFolder: appFolder)
        try Task.checkCancellation()
        let extractDir = input.workDir.appendingPathComponent("extract", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try extractGuarded(zip: input.zip, into: extractDir, limits: limits, log: input.workDir.appendingPathComponent("extract.log"))
        // 이름만 읽고 앱 안은 열지 않는다. 읽지 못하면 빈 목록 → 거부.
        try Task.checkCancellation()
        let topLevel = (try? fm.contentsOfDirectory(atPath: extractDir.path)) ?? []
        if let problem = UpdateArchive.extractedTopLevelProblem(topLevel, appFolder: appFolder) { throw OnePercentError.archiveRejected(problem) }

        let app = extractDir.appendingPathComponent(appFolder)
        // 🔒 아래 어떤 검사보다 먼저: 푼 결과가 추출 폴더 안의 실제 폴더인가. 링크면 이후 검사가 링크 너머 번들에 적용된다. 읽기 실패는 링크로 본다.
        let values = try? app.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard UpdateDecision.isSafeExtractedApp(
            isSymbolicLink: values?.isSymbolicLink ?? true,
            isDirectory: values?.isDirectory ?? false,
            resolvedAppPath: app.resolvingSymlinksInPath().standardizedFileURL.path,
            resolvedExtractDirPath: extractDir.resolvingSymlinksInPath().standardizedFileURL.path
        ) else { throw OnePercentError.verificationFailed([.notARealFolder]) }
        guard fm.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path) else {
            throw OnePercentError.archiveRejected(.missingApp(appFolder: appFolder))
        }
        if !UpdateArchive.escapingLinks(in: app).isEmpty { throw OnePercentError.archiveRejected(.escapingLink(appFolder: appFolder)) }
        // 2026-11-20 (PR #1 보안 리뷰 P2-1): ZIP 이 정한 권한·ACL 을 그대로 설치하지 않는다(관리자 경로와 같은 정리).
        // 코드 서명은 권한·ACL 을 덮지 않아 서명 검사로는 못 잡는다. setuid·setgid·그룹/다른 사용자 쓰기와 ACL 을 벗긴다.
        try normalizePermissions(of: app)

        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        let bundleVersion = UpdateDecision.bundleVersion(info: info, configuration: configuration)
        let build = info?["CFBundleVersion"] as? String
        let requirement = UpdateDecision.codeRequirement(bundleIdentifier: configuration.bundleIdentifier, team: configuration.teamIdentifier)
        var failures: [VerificationFailure] = []
        if info?["CFBundleIdentifier"] as? String != configuration.bundleIdentifier { failures.append(.bundleIdentifierMismatch) }
        // 2026-11-20 (리뷰 P2-3): 검사 사이마다 취소를 본다 — 서명·공증 검사는 수 초씩 걸린다.
        try Task.checkCancellation()
        if !checks.signedByTeam(app, requirement) { failures.append(.notSignedByTeam) }
        try Task.checkCancellation()
        if !checks.codesignValid(app, requirement) { failures.append(.codeSignatureInvalid) }
        try Task.checkCancellation()
        if !checks.notarizationAccepted(app) { failures.append(.notarizationRejected) }
        try Task.checkCancellation()
        if input.checkIncrease, let problem = UpdateDecision.increaseProblem(
            currentVersion: input.currentVersion, currentBuild: input.currentBuild,
            newVersion: bundleVersion, newBuild: build, configuration: configuration) {
            failures.append(problem)
        }
        if !UpdateDecision.bundleMatchesRelease(bundleVersion: bundleVersion, releaseVersion: input.releaseVersion, configuration: configuration) {
            failures.append(.releaseMismatch(bundleVersion: bundleVersion, releaseVersion: input.releaseVersion))
        }
        guard failures.isEmpty else { throw OnePercentError.verificationFailed(failures) }
        guard let shortVersion = info?["CFBundleShortVersionString"] as? String, let build else {
            throw OnePercentError.verificationFailed([.versionUnreadable])
        }
        // 검증을 통과한 우리 번들이므로 격리 속성을 벗긴다(App Translocation 방지). URLSession 다운로드엔 보통 붙지 않지만 붙어 있어도 되게.
        stripQuarantine(at: app)
        return VerifiedUpdate(app: app, identity: .init(bundleID: configuration.bundleIdentifier, version: shortVersion, build: build))
    }

    /// Reads only the ZIP's central directory (at most 4 MiB) and judges it.
    static func inspectArchive(_ zip: URL, limits: ArchiveLimits, appFolder: String) throws {
        do {
            let handle = try FileHandle(forReadingFrom: zip)
            defer { try? handle.close() }
            let size = Int(try handle.seekToEnd())
            let tailLength = min(size, UpdateArchive.tailBytes)
            try handle.seek(toOffset: UInt64(size - tailLength))
            let tail = [UInt8](try handle.read(upToCount: tailLength) ?? Data())
            guard let location = UpdateArchive.directoryLocation(tail: tail, fileSize: size) else {
                throw OnePercentError.archiveRejected(.unreadableListing)
            }
            try handle.seek(toOffset: UInt64(location.offset))
            let directory = [UInt8](try handle.read(upToCount: location.size) ?? Data())
            guard directory.count == location.size,
                  let entries = UpdateArchive.entries(centralDirectory: directory, expectedCount: location.entries) else {
                throw OnePercentError.archiveRejected(.unreadableListing)
            }
            if let problem = UpdateArchive.problem(entries, limits: limits, appFolder: appFolder) { throw OnePercentError.archiveRejected(problem) }
        } catch let error as OnePercentError {
            throw error
        } catch {
            throw OnePercentError.archiveRejected(.unreadableListing)
        }
    }

    /// Unpacks while watching bytes on disk, item count and time; stops and deletes the partial result at the first limit.
    /// Between crossing a limit and stopping (0.05 s) a little more may be written, but the disk cannot be filled.
    /// `tool`/`arguments` are swapped only in tests (a slow fake unpacker).
    static func extractGuarded(zip: URL, into directory: URL, limits: ArchiveLimits, log: URL,
                               tool: String = "/usr/bin/ditto", arguments: [String]? = nil,
                               interval: TimeInterval = 0.05) throws {
        let fm = FileManager.default
        guard fm.createFile(atPath: log.path, contents: nil), let output = try? FileHandle(forWritingTo: log) else {
            throw OnePercentError.extractFailed("log")
        }
        defer { try? output.close() }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments ?? ["-x", "-k", zip.path, directory.path]
        task.standardOutput = output
        task.standardError = output
        let started = Date()
        do { try task.run() } catch { throw OnePercentError.extractFailed(error.localizedDescription) }
        var stopReason: ArchiveProblem?
        var cancelled = false
        while task.isRunning {
            Thread.sleep(forTimeInterval: interval)
            if Task.isCancelled {
                cancelled = true
                task.terminate()
                for _ in 0..<20 where task.isRunning { Thread.sleep(forTimeInterval: 0.05) }
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                break
            }
            let usage = diskUsage(of: directory, stopAfter: limits.entries)
            if let reason = UpdateArchive.extractionProblem(bytes: usage.bytes, items: usage.items,
                                                            elapsed: Date().timeIntervalSince(started), limits: limits) {
                stopReason = reason
                task.terminate()
                for _ in 0..<20 where task.isRunning { Thread.sleep(forTimeInterval: 0.05) }
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                break
            }
        }
        task.waitUntilExit()
        if cancelled {
            for item in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: item) }
            throw CancellationError()
        }
        if stopReason == nil {
            let usage = diskUsage(of: directory, stopAfter: limits.entries)
            stopReason = UpdateArchive.extractionProblem(bytes: usage.bytes, items: usage.items,
                                                         elapsed: Date().timeIntervalSince(started), limits: limits)
        }
        if let stopReason {
            for item in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: item)
            }
            onePercentLog.error("extraction stopped: \(String(describing: stopReason), privacy: .public)")
            throw OnePercentError.archiveRejected(stopReason)
        }
        guard task.terminationStatus == 0 else {
            let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw OnePercentError.extractFailed(clip(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    /// Bytes on disk (regular files: the larger of logical and allocated size; every item: its extended attributes)
    /// and item count. Stops counting past `limit` items.
    /// 2026-11-20 (PR #1 보안 리뷰 P3-3): 폴더에 붙은 확장 속성은 세지 않아, 12 MB 를 붙인 ZIP 이 5 MB 상한을 지났다.
    static func diskUsage(of directory: URL, stopAfter limit: Int) -> (bytes: UInt64, items: Int) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys, options: [],
                                                          errorHandler: { _, _ in true }) else { return (0, 0) }
        var bytes: UInt64 = 0
        var items = 0
        for case let url as URL in walker {
            items += 1
            if items > limit { break }
            bytes &+= extendedAttributeBytes(url.path)
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            bytes &+= UInt64(max(values.fileSize ?? 0, values.totalFileAllocatedSize ?? 0))
        }
        return (bytes, items)
    }

    /// The total size of an item's extended attributes (the item itself, not a link's target).
    static func extendedAttributeBytes(_ path: String) -> UInt64 {
        let length = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        guard length > 0 else { return 0 }
        var names = [CChar](repeating: 0, count: length)
        guard listxattr(path, &names, length, XATTR_NOFOLLOW) == length else { return 0 }
        var total: UInt64 = 0
        var start = 0
        for index in 0..<length where names[index] == 0 {
            let size = names.withUnsafeBufferPointer { buffer in
                getxattr(path, buffer.baseAddress! + start, nil, 0, 0, XATTR_NOFOLLOW)
            }
            if size > 0 { total &+= UInt64(size) }
            start = index + 1
        }
        return total
    }

    /// External text in messages and logs is cut short. 2026-11-20 (보안 리뷰 P3-7).
    static func clip(_ text: String, _ limit: Int = 300) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }

    static func normalizePermissions(of app: URL) throws {
        for arguments in [["-R", "u-s,g-s,go-w", app.path], ["-RN", app.path]] {
            let result = ProcessRunner.run("/bin/chmod", arguments)
            guard result.status == 0 else { throw OnePercentError.extractFailed(clip(result.output)) }
        }
    }

    static func stripQuarantine(at app: URL) {
        let result = ProcessRunner.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        if result.status != 0 && !result.output.isEmpty && !result.output.contains("No such xattr") {
            onePercentLog.notice("quarantine strip returned \(result.status): \(result.output, privacy: .public)")
        }
    }
}
