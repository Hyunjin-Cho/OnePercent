import Foundation
import Testing
@testable import OnePercent

/// Real `ditto` and real files in a temporary folder — only the three Apple-signature checks are swapped.
/// 2026-11-20: 하늘키보드 `UpdateInstallTests`(#226) 의 조립·감시·사용자 교체 시험을 옮겼다.
@Suite struct InstallPipelineTests {
    let config = Fixture.configuration()

    func attempt(in root: URL, _ name: String, version: String, build: String = "999", tag: String, current: String = "1.0",
                 checks: BundleChecks = .accepting, prepare: ((URL) throws -> Void)? = nil) throws -> (Result<VerifiedUpdate, Error>, URL) {
        let fm = FileManager.default
        let folder = root.appendingPathComponent(name)
        let source = folder.appendingPathComponent("src")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let app = try Fixture.makeApp(source.appendingPathComponent("TestApp.app"), version: version, build: build)
        let archive = folder.appendingPathComponent("update.zip")
        if let prepare { try prepare(archive) } else { #expect(Fixture.zip(app, to: archive)) }
        let work = folder.appendingPathComponent("work")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let input = UpdateVerifier.Input(zip: archive, workDir: work, configuration: config, currentVersion: current,
                                         currentBuild: "100", releaseVersion: tag)
        return (Result { try UpdateVerifier.extractAndVerify(input, checks: checks) }, work.appendingPathComponent("extract"))
    }

    func failures(_ result: Result<VerifiedUpdate, Error>) -> [VerificationFailure]? {
        if case .failure(OnePercentError.verificationFailed(let list)) = result { return list }
        return nil
    }

    @Test func verifiesTheExtractedApp() throws {
        let root = try Fixture.temporaryRoot("flow")
        defer { try? FileManager.default.removeItem(at: root) }
        let log = CallLog()
        let recording = BundleChecks(signedByTeam: { app, _ in log.add("team:" + app.path); return true },
                                     codesignValid: { app, _ in log.add("codesign:" + app.path); return true },
                                     notarizationAccepted: { log.add("spctl:" + $0.path); return true })
        let (ok, extract) = try attempt(in: root, "ok", version: "1.1", tag: "1.1", checks: recording)
        let verified = try ok.get()
        #expect(verified.app.path == extract.appendingPathComponent("TestApp.app").path)
        #expect(verified.identity == VerifiedIdentity(bundleID: Fixture.bundleID, version: "1.1", build: "999"))
        #expect(log.all.count == 3 && log.all.allSatisfy { $0.hasSuffix("/extract/TestApp.app") }, "signature checks run on the extracted app only")
    }

    /// 2026-11-20 (보안 리뷰 P2-1): ZIP 이 정한 그룹·다른 사용자 쓰기 권한과 ACL 은 설치 전에 벗긴다.
    @Test func permissionsFromTheZipAreNotKept() throws {
        let root = try Fixture.temporaryRoot("modes")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let (result, _) = try attempt(in: root, "loose", version: "1.1", tag: "1.1") { archive in
            let app = try Fixture.makeApp(archive.deletingLastPathComponent().appendingPathComponent("l/TestApp.app"), version: "1.1", build: "999")
            let file = app.appendingPathComponent("Contents/MacOS/TestApp")
            try fm.setAttributes([.posixPermissions: 0o777], ofItemAtPath: file.path)
            try fm.setAttributes([.posixPermissions: 0o777], ofItemAtPath: app.appendingPathComponent("Contents").path)
            #expect(Fixture.tool("/bin/chmod", ["+a", "group:everyone allow write,delete,append", file.path]) == 0)
            #expect(Fixture.zip(app, to: archive))
        }
        let app = try result.get().app
        for path in [app.appendingPathComponent("Contents/MacOS/TestApp").path, app.appendingPathComponent("Contents").path] {
            let mode = (try fm.attributesOfItem(atPath: path)[.posixPermissions] as? Int) ?? 0o777
            #expect(mode & 0o022 == 0, "\(path): \(String(mode, radix: 8))")
        }
        let listing = Process(), out = Pipe()
        listing.executableURL = URL(fileURLWithPath: "/bin/ls")
        listing.arguments = ["-le", app.appendingPathComponent("Contents/MacOS/TestApp").path]
        listing.standardOutput = out
        try listing.run(); listing.waitUntilExit()
        #expect(!String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains(" allow "), "no ACL left")
    }

    /// 2026-11-22 (#18): 실제 ditto ZIP — 한글·악센트 이름 앱이 목록 검사부터 검증까지 통과한다(설정은 NFC, ZIP 은 NFD).
    @Test func composedAppNameThroughThePipeline() throws {
        let root = try Fixture.temporaryRoot("composed")
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["닦아", "Caf\u{E9}"] {
            var configuration = Fixture.configuration()
            configuration.appName = name.precomposedStringWithCanonicalMapping
            configuration.assetName = { "App_\($0).zip" }
            #expect(configuration.problems.isEmpty, "\(configuration.problems)")
            let folder = root.appendingPathComponent(UUID().uuidString)
            let app = try Fixture.makeApp(folder.appendingPathComponent("src/\(configuration.appName).app"), version: "1.1", build: "999")
            let zip = folder.appendingPathComponent("update.zip")
            #expect(Fixture.zip(app, to: zip))
            let first = (Fixture.parse([UInt8](try Data(contentsOf: zip))) ?? []).first?.name ?? ""
            #expect(Array(first.utf8) == Array((configuration.appName + ".app/").decomposedStringWithCanonicalMapping.utf8),
                    "premise: ditto stores \(name) decomposed")
            let work = folder.appendingPathComponent("work")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let input = UpdateVerifier.Input(zip: zip, workDir: work, configuration: configuration, currentVersion: "1.0",
                                             currentBuild: "100", releaseVersion: "1.1")
            let verified = try UpdateVerifier.extractAndVerify(input, checks: .accepting)
            #expect(verified.identity.version == "1.1" && verified.identity.build == "999", "\(name)")
        }
    }

    @Test func refusesWrongVersionsAndSignatures() throws {
        let root = try Fixture.temporaryRoot("refuse")
        defer { try? FileManager.default.removeItem(at: root) }
        let (older, _) = try attempt(in: root, "older", version: "1.1", tag: "1.2")
        #expect(failures(older) == [.releaseMismatch(bundleVersion: "1.1", releaseVersion: "1.2")], "not the announced version")
        let (lower, _) = try attempt(in: root, "lower", version: "0.9", build: "50", tag: "0.9")
        #expect(failures(lower)?.contains(.versionNotHigher) == true)
        let (unsigned, _) = try attempt(in: root, "unsigned", version: "1.1", tag: "1.1",
                                        checks: BundleChecks(signedByTeam: { _, _ in false }, codesignValid: { _, _ in false },
                                                             notarizationAccepted: { _ in false }))
        #expect(failures(unsigned) == [.notSignedByTeam, .codeSignatureInvalid, .notarizationRejected])
        let (otherID, _) = try attempt(in: root, "other-id", version: "1.1", tag: "1.1") { archive in
            let app = try Fixture.makeApp(archive.deletingLastPathComponent().appendingPathComponent("o/TestApp.app"), version: "1.1",
                                          build: "999", identifier: "com.example.other")
            #expect(Fixture.zip(app, to: archive))
        }
        #expect(failures(otherID) == [.bundleIdentifierMismatch])
    }

    /// 2026-09-21 (하늘키보드 #19 P3-1): 맨 위가 링크면 서명 검사 전에 거부한다.
    @Test func refusesALinkedTopLevel() throws {
        let root = try Fixture.temporaryRoot("toplink")
        defer { try? FileManager.default.removeItem(at: root) }
        let log = CallLog()
        let checks = BundleChecks(signedByTeam: { _, _ in log.add("x"); return true }, codesignValid: { _, _ in true }, notarizationAccepted: { _ in true })
        let (linked, _) = try attempt(in: root, "link", version: "1.1", tag: "1.1", checks: checks) { archive in
            let staging = archive.deletingLastPathComponent().appendingPathComponent("linkzip")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: staging.appendingPathComponent("TestApp.app"),
                                                       withDestinationURL: archive.deletingLastPathComponent().appendingPathComponent("src/TestApp.app"))
            #expect(Fixture.tool("/usr/bin/zip", ["-q", "-y", "-r", archive.path, "TestApp.app"], in: staging) == 0)
        }
        var refused = failures(linked) != nil
        if case .failure(OnePercentError.archiveRejected) = linked { refused = true }
        #expect(refused && log.all.isEmpty)
    }

    /// 2026-11-20 (Fable 리뷰): 앱 안의 링크 아래에 다른 항목을 둔 ZIP 은 목록 단계에서 거부한다(ditto 에 기대지 않는다).
    @Test func refusesEntriesUnderALink() throws {
        let root = try Fixture.temporaryRoot("innerlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let (result, extract) = try attempt(in: root, "inner", version: "1.1", tag: "1.1") { archive in
            let staging = archive.deletingLastPathComponent().appendingPathComponent("z")
            let app = try Fixture.makeApp(staging.appendingPathComponent("TestApp.app"), version: "1.1", build: "999")
            let outside = root.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("Contents/Res"), withDestinationURL: outside)
            // Info-ZIP keeps the link (-y) and, with a second pass, stores a file "under" it.
            #expect(Fixture.tool("/usr/bin/zip", ["-q", "-y", "-r", archive.path, "TestApp.app"], in: staging) == 0)
            try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Res"))
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Res"), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: app.appendingPathComponent("Contents/Res/planted"))
            #expect(Fixture.tool("/usr/bin/zip", ["-q", archive.path, "TestApp.app/Contents/Res/planted"], in: staging) == 0)
        }
        #expect(throws: OnePercentError.archiveRejected(.linkedEntry(appFolder: "TestApp.app"))) { try result.get() }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("outside/planted").path), "nothing written outside")
        #expect(!FileManager.default.fileExists(atPath: extract.appendingPathComponent("TestApp.app").path), "nothing unpacked")
    }

    @Test func refusesItemsOutsideTheApp() throws {
        let root = try Fixture.temporaryRoot("outside")
        defer { try? FileManager.default.removeItem(at: root) }
        let (outside, extract) = try attempt(in: root, "outside", version: "1.1", tag: "1.1") { archive in
            let staging = archive.deletingLastPathComponent().appendingPathComponent("o")
            try Fixture.makeApp(staging.appendingPathComponent("TestApp.app"), version: "1.1", build: "999")
            try Data("x".utf8).write(to: staging.appendingPathComponent("extra.txt"))
            #expect(Fixture.tool("/usr/bin/zip", ["-q", "-r", archive.path, "TestApp.app", "extra.txt"], in: staging) == 0)
        }
        #expect(throws: OnePercentError.archiveRejected(.outsideApp(appFolder: "TestApp.app"))) { try outside.get() }
        #expect(!FileManager.default.fileExists(atPath: extract.appendingPathComponent("TestApp.app").path))
    }

    /// 2026-11-13 (하늘키보드 #226 P3-5): 목록엔 앱 안 이름, 머리글엔 앱 밖 이름 — 풀린 맨 위를 보고 거부한다.
    @Test func refusesHeaderNamesThatDifferFromTheListing() throws {
        let root = try Fixture.temporaryRoot("header")
        defer { try? FileManager.default.removeItem(at: root) }
        let good = "TestApp.app/Contents/Resources/aaaaaaaaaaaaaaaa.txt"
        let evil = "OUTSIDE_APP_" + String(repeating: "c", count: good.count - "OUTSIDE_APP_".count - 4) + ".txt"
        func craft(_ archive: URL, local last: String) throws {
            let app = try Fixture.makeApp(archive.deletingLastPathComponent().appendingPathComponent("c/TestApp.app"), version: "1.1", build: "999")
            let plist = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            let dirs = ["TestApp.app/", "TestApp.app/Contents/", "TestApp.app/Contents/Resources/"]
            try Fixture.craftedZip(dirs.map { ($0, $0, Data()) } + [("TestApp.app/Contents/Info.plist", "TestApp.app/Contents/Info.plist", plist),
                                                                   (last, good, Data("x".utf8))]).write(to: archive)
            try UpdateVerifier.inspectArchive(archive, limits: .standard, appFolder: "TestApp.app")
        }
        let log = CallLog()
        let checks = BundleChecks(signedByTeam: { _, _ in log.add("x"); return true }, codesignValid: { _, _ in true }, notarizationAccepted: { _ in true })
        let (header, extract) = try attempt(in: root, "evil", version: "1.1", tag: "1.1", checks: checks) { try craft($0, local: evil) }
        #expect(throws: OnePercentError.archiveRejected(.unexpectedTopLevel(appFolder: "TestApp.app", count: 2))) { try header.get() }
        #expect(log.all.isEmpty, "refused before any signature check")
        #expect(FileManager.default.fileExists(atPath: extract.appendingPathComponent(evil).path), "ditto unpacks by header name — why the check exists")
        let (same, _) = try attempt(in: root, "same", version: "1.1", tag: "1.1") { try craft($0, local: good) }
        #expect((try? same.get()) != nil)
    }

    @Test func refusesAZipWithoutTheApp() throws {
        let root = try Fixture.temporaryRoot("noapp")
        defer { try? FileManager.default.removeItem(at: root) }
        let (missing, _) = try attempt(in: root, "empty", version: "1.1", tag: "1.1") { archive in
            let staging = archive.deletingLastPathComponent().appendingPathComponent("e")
            try FileManager.default.createDirectory(at: staging.appendingPathComponent("TestApp.app/Contents"), withIntermediateDirectories: true)
            #expect(Fixture.zip(staging.appendingPathComponent("TestApp.app"), to: archive))
        }
        #expect(throws: OnePercentError.archiveRejected(.missingApp(appFolder: "TestApp.app"))) { try missing.get() }
    }

    /// A slow fake unpacker: stops as soon as a limit is passed.
    @Test func stopsUnpackingAtTheLimit() throws {
        let root = try Fixture.temporaryRoot("guard")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let writer = root.appendingPathComponent("slow-writer.sh")
        try """
        #!/bin/sh
        mkdir -p "$3/TestApp.app/Contents"
        big=$(/usr/bin/head -c 65536 /dev/zero | /usr/bin/tr '\\0' 'a')
        i=0
        while [ $i -lt 400 ]; do
            case "$1" in
            bytes) printf '%s' "$big" > "$3/TestApp.app/Contents/chunk$i" ;;
            items) : > "$3/TestApp.app/Contents/item$i" ;;
            esac
            i=$((i + 1))
            /bin/sleep 0.01
        done
        """.write(to: writer, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: writer.path)
        let archive = root.appendingPathComponent("unused.zip")
        try Data().write(to: archive)
        for (mode, limits) in [("bytes", ArchiveLimits(entries: 10_000, bytes: 1024 * 1024, seconds: 60)),
                               ("items", ArchiveLimits(entries: 20, bytes: 1 << 30, seconds: 60)),
                               ("time", ArchiveLimits(entries: 10_000, bytes: 1 << 30, seconds: 0.5))] {
            let target = root.appendingPathComponent("out-\(mode)")
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let started = Date()
            var rejected = false
            do {
                try UpdateVerifier.extractGuarded(zip: archive, into: target, limits: limits, log: root.appendingPathComponent("\(mode).log"),
                                                  tool: writer.path, arguments: [mode, archive.path, target.path])
            } catch OnePercentError.archiveRejected { rejected = true }
            #expect(rejected, "\(mode)")
            #expect(Date().timeIntervalSince(started) < 3, "\(mode): stops right away")
            #expect(((try? fm.contentsOfDirectory(atPath: target.path)) ?? ["?"]).isEmpty, "\(mode): partial result deleted")
        }
        // A ZIP that understates its sizes passes the listing but is stopped by what lands on disk (real ditto).
        let bomb = try Fixture.makeApp(root.appendingPathComponent("bomb/TestApp.app"), version: "1.1", build: "1", payload: 8 * 1024 * 1024)
        let lying = root.appendingPathComponent("lying.zip")
        #expect(Fixture.zip(bomb, to: lying) && Fixture.understate(lying))
        let small = ArchiveLimits(entries: 2_000, bytes: 1024 * 1024, seconds: 60)
        try UpdateVerifier.inspectArchive(lying, limits: small, appFolder: "TestApp.app")
        let out = root.appendingPathComponent("out-lying")
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        #expect(throws: OnePercentError.self) {
            try UpdateVerifier.extractGuarded(zip: lying, into: out, limits: small, log: root.appendingPathComponent("lying.log"))
        }
        #expect(((try? fm.contentsOfDirectory(atPath: out.path)) ?? ["?"]).isEmpty)
    }

    // MARK: - User-owned replacement (하늘키보드 #226 F-9)

    @Test func userReplacementRechecksTheCopy() throws {
        let root = try Fixture.temporaryRoot("replace")
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = VerifiedIdentity(bundleID: Fixture.bundleID, version: "1.1", build: "999")
        let requirement = UpdateDecision.codeRequirement(bundleIdentifier: Fixture.bundleID, team: Fixture.team)
        for accept in [true, false] {
            let folder = root.appendingPathComponent(accept ? "accepted" : "rejected")
            let installed = try Fixture.makeApp(folder.appendingPathComponent("Applications/TestApp.app"), version: "1.0", build: "100", marker: "old")
            let incoming = try Fixture.makeApp(folder.appendingPathComponent("extract/TestApp.app"), version: "1.1", build: "999", marker: "new")
            var checked: [URL] = []
            var installedDuringCheck: String?
            let thrown = (try? UpdateReplacement.replaceAtomically(destination: installed, with: VerifiedUpdate(app: incoming, identity: identity),
                                                                    requirement: requirement) { copy, expected in
                checked.append(copy)
                installedDuringCheck = Fixture.marker(installed)
                return accept && expected == identity
            }) == nil
            // 2026-11-22 (#19): 사본은 설치된 앱 옆의 새 staging 폴더 안에 있다.
            let stagingFolder = checked.first?.deletingLastPathComponent()
            #expect(checked.count == 1 && checked[0].path != incoming.path
                    && stagingFolder?.deletingLastPathComponent().path == installed.deletingLastPathComponent().path
                    && stagingFolder?.lastPathComponent.hasPrefix(UpdateReplacement.stagingPrefix(for: installed)) == true,
                    "the copy next to the installed app is re-checked, not the temporary original")
            #expect(installedDuringCheck == "old", "nothing touched before the check")
            #expect(thrown == !accept)
            #expect(Fixture.marker(installed) == (accept ? "new" : "old"))
            let names = (try? FileManager.default.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path)) ?? []
            #expect(names == ["TestApp.app"], "no staging left: \(names)")
        }
        let copy = try Fixture.makeApp(root.appendingPathComponent("identity/copy.app"), version: "1.1", build: "999")
        #expect(UpdateReplacement.copyMatchesIdentity(at: copy, identity: identity))
        for other in [VerifiedIdentity(bundleID: "com.example.other", version: "1.1", build: "999"),
                      VerifiedIdentity(bundleID: Fixture.bundleID, version: "1.2", build: "999"),
                      VerifiedIdentity(bundleID: Fixture.bundleID, version: "1.1", build: "998")] {
            #expect(!UpdateReplacement.copyMatchesIdentity(at: copy, identity: other))
        }
        let link = root.appendingPathComponent("identity/link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: copy)
        #expect(!UpdateReplacement.copyMatchesIdentity(at: link, identity: identity))
        #expect(!UpdateReplacement.isIntactCopy(at: copy, identity: identity, requirement: requirement), "real codesign refuses an unsigned copy")
    }

    /// 2026-11-22 (#19): 한 시간 전에 빌드된 앱을 교체하는 도중 같은 앱이 또 실행돼 시작 정리(10분 기준)가 돌아도
    /// 진행 중인 staging 은 남고 교체는 끝난다. 예전엔 사본이 원본의 옛 시각을 물려받아 지워졌고 교체가 실패했다.
    @Test func aSwapInProgressSurvivesALaunchCleanup() throws {
        let root = try Fixture.temporaryRoot("swap-age")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let installed = try Fixture.makeApp(root.appendingPathComponent("Applications/TestApp.app"), version: "1.0", build: "1", marker: "old")
        let incoming = try Fixture.makeApp(root.appendingPathComponent("extract/TestApp.app"), version: "1.1", build: "2", marker: "new")
        let hourAgo = Date().addingTimeInterval(-3600)
        for path in [incoming.path, incoming.appendingPathComponent("Contents").path] {
            try fm.setAttributes([.modificationDate: hourAgo], ofItemAtPath: path)
        }
        var removedDuringSwap = -1
        try UpdateReplacement.replaceAtomically(destination: installed,
                                                with: VerifiedUpdate(app: incoming, identity: VerifiedIdentity(bundleID: Fixture.bundleID,
                                                                                                                version: "1.1", build: "2")),
                                                requirement: "unused") { _, _ in
            removedDuringSwap = UpdateReplacement.removeLeftovers(installedApp: installed, workPrefix: "OnePercent-none-",
                                                                  temporaryDirectory: root.appendingPathComponent("extract"))
            return true
        }
        #expect(removedDuringSwap == 0, "the staging folder of the swap in progress is younger than ten minutes")
        #expect(Fixture.marker(installed) == "new")
        #expect((try fm.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path)) == ["TestApp.app"], "no staging left")
    }

    /// The public entry point an app's own uninstaller calls.
    @Test func publicLeftoverCleanup() throws {
        let root = try Fixture.temporaryRoot("public-leftovers")
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = try Fixture.makeApp(root.appendingPathComponent("Applications/TestApp.app"), version: "1.0", build: "1")
        let staging = root.appendingPathComponent("Applications/.TestApp.app.onepercent-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        #expect(OnePercentUpdater.removeLeftovers(configuration: Fixture.configuration(), installedApp: installed) == 0, "fresh: kept")
        #expect(OnePercentUpdater.removeLeftovers(configuration: Fixture.configuration(), installedApp: installed, olderThan: 0) >= 1)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    /// 2026-11-20 (Fable 리뷰 4): 강제 종료로 남은 staging·작업 폴더를 다음 실행에 치운다 — 이 앱 것, 이 사용자 것, 링크 아닌 것만.
    @Test func removesOnlyOurLeftovers() throws {
        let root = try Fixture.temporaryRoot("leftovers")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let apps = root.appendingPathComponent("Applications")
        let tmp = root.appendingPathComponent("tmp")
        let installed = try Fixture.makeApp(apps.appendingPathComponent("TestApp.app"), version: "1.0", build: "1")
        let id = { UUID().uuidString }
        let ours = ".TestApp.app.onepercent-" + id(), otherApp = ".Other.app.onepercent-" + id(), backup = ".TestApp.app.old-" + id()
        for name in [ours, otherApp, backup, ".TestApp.app.onepercent-notauuid"] {
            try fm.createDirectory(at: apps.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let work = "OnePercent-com.example.testapp-" + id(), otherWork = "OnePercent-com.example.other-" + id()
        // 2026-11-20 (리뷰): 접두어가 같은 다른 번들(`com.example.testapp-helper`)의 작업 폴더는 지우지 않는다.
        let helper = "OnePercent-com.example.testapp-helper-" + id()
        for name in [work, otherWork, helper] { try fm.createDirectory(at: tmp.appendingPathComponent(name), withIntermediateDirectories: true) }
        let target = root.appendingPathComponent("keep")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let link = "OnePercent-com.example.testapp-" + id()
        try fm.createSymbolicLink(at: tmp.appendingPathComponent(link), withDestinationURL: target)
        #expect(UpdateReplacement.removeLeftovers(installedApp: installed, workPrefix: "OnePercent-com.example.testapp-", temporaryDirectory: tmp) == 0,
                "fresh items (another instance may be updating right now) stay")
        let removed = UpdateReplacement.removeLeftovers(installedApp: installed, workPrefix: "OnePercent-com.example.testapp-",
                                                        temporaryDirectory: tmp, olderThan: 0)
        #expect(removed == 2)
        #expect(Set(try fm.contentsOfDirectory(atPath: apps.path)) == ["TestApp.app", otherApp, backup, ".TestApp.app.onepercent-notauuid"],
                "another app's staging, the administrator backup and non-UUID names stay")
        #expect(Set(try fm.contentsOfDirectory(atPath: tmp.path)) == [otherWork, helper, link])
        #expect(fm.fileExists(atPath: target.path), "links are never followed or removed")
    }
}
