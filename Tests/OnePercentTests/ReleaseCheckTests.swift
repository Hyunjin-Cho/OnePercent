import Foundation
import Testing
@testable import OnePercent

/// `onepercent-check` 의 바탕. 2026-11-20 (PR #1 코드 리뷰 P1-1): 예전엔 시험이 0건이었고 날짜형 규칙에서 정상 ZIP 도 늘 거부됐다.
@Suite struct ReleaseCheckTests {
    func releaseZip(_ name: String, version: String, build: String, extraInfo: [String: Any] = [:]) throws -> (URL, URL) {
        let root = try Fixture.temporaryRoot("check-\(name)")
        let app = try Fixture.makeApp(root.appendingPathComponent("src/TestApp.app"), version: version, build: build, extraInfo: extraInfo)
        let zip = root.appendingPathComponent("TestApp_\(version).zip")
        #expect(Fixture.zip(app, to: zip))
        return (root, zip)
    }

    @Test func numericAndCalendarZipsPass() throws {
        let (root, zip) = try releaseZip("numeric", version: "1.1", build: "2")
        defer { try? FileManager.default.removeItem(at: root) }
        let report = OnePercentReleaseCheck.check(zip: zip, tag: "1.1", configuration: Fixture.configuration(), checkSignature: false)
        #expect(report.problems.isEmpty && report.bundleVersion == "1.1" && report.build == "2", "\(report.problems)")

        let (calendarRoot, calendarZip) = try releaseZip("calendar", version: "2026.11.17", build: "5")
        defer { try? FileManager.default.removeItem(at: calendarRoot) }
        let calendar = OnePercentReleaseCheck.check(zip: calendarZip, tag: "2026.11.17",
                                                    configuration: Fixture.configuration(scheme: .calendar()), checkSignature: false)
        #expect(calendar.problems.isEmpty, "\(calendar.problems)")
    }

    @Test func comparesWithThePreviousRelease() throws {
        let (root, zip) = try releaseZip("previous", version: "1.1", build: "2")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = Fixture.configuration()
        #expect(OnePercentReleaseCheck.check(zip: zip, tag: "1.1", configuration: config, checkSignature: false,
                                             previousVersion: "1.0", previousBuild: "1").problems.isEmpty)
        let sameBuild = OnePercentReleaseCheck.check(zip: zip, tag: "1.1", configuration: config, checkSignature: false,
                                                     previousVersion: "1.0", previousBuild: "2")
        #expect(sameBuild.problems.count == 1 && sameBuild.problems[0].contains("CFBundleVersion"), "forgot to raise the build: \(sameBuild.problems)")
        #expect(sameBuild.problems.first?.hasSuffix("(verificationFailed: buildNotHigher)") == true, "the same code apps show (#35)")
        let older = OnePercentReleaseCheck.check(zip: zip, tag: "1.1", configuration: config, checkSignature: false,
                                                 previousVersion: "1.2", previousBuild: "1")
        #expect(older.problems.count == 1, "\(older.problems)")
    }

    /// 2026-11-22 (#20): 앱이 바꾼 설정으로 본다 — 내려받기 상한(ZIP 크기), 풀기 상한, 자산 이름, 빌드 규칙.
    @Test func usesTheAppsOwnConfiguration() throws {
        let (root, zip) = try releaseZip("own-config", version: "1.1", build: "2")
        defer { try? FileManager.default.removeItem(at: root) }
        var small = Fixture.configuration()
        small.limits = Limits(maxAssetBytes: 10, maxMetadataBytes: 1024, archive: .standard)
        let tooBig = OnePercentReleaseCheck.check(zip: zip, tag: "1.1", configuration: small, checkSignature: false)
        #expect(tooBig.problems.contains { $0.contains("download limit") }, "\(tooBig.problems)")
        var few = Fixture.configuration()
        few.limits = Limits(maxAssetBytes: Limits.standard.maxAssetBytes, maxMetadataBytes: 1024,
                            archive: ArchiveLimits(entries: 2, bytes: 1 << 30, seconds: 60))
        #expect(OnePercentReleaseCheck.check(zip: zip, tag: "1.1", configuration: few, checkSignature: false).problems.count == 1,
                "the app's unpacking limits apply")
        let renamed = root.appendingPathComponent("Custom-1.1.zip")
        try FileManager.default.copyItem(at: zip, to: renamed)
        var custom = Fixture.configuration()
        custom.assetName = { "Custom-\($0).zip" }
        #expect(OnePercentReleaseCheck.check(zip: renamed, tag: "1.1", configuration: custom, checkSignature: false).problems.isEmpty)
        #expect(!OnePercentReleaseCheck.check(zip: zip, tag: "1.1", configuration: custom, checkSignature: false).problems.isEmpty,
                "the default name is wrong for an app with its own assetName")
        var sameBuildAllowed = Fixture.configuration(requireBuildIncrease: false)
        sameBuildAllowed.limits = .standard
        #expect(OnePercentReleaseCheck.check(zip: zip, tag: "1.1", configuration: sameBuildAllowed, checkSignature: false,
                                             previousVersion: "1.0", previousBuild: "2").problems.isEmpty, "requireBuildIncrease: false")
    }

    @Test func setupMistakes() throws {
        let (root, zip) = try releaseZip("mistakes", version: "1.1", build: "2")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = Fixture.configuration()
        let wrongTag = OnePercentReleaseCheck.check(zip: zip, tag: "1.2", configuration: config, checkSignature: false)
        #expect(wrongTag.problems.contains { $0.contains("asset name must be TestApp_1.2.zip") })
        #expect(wrongTag.problems.contains { $0.contains("1.1") && $0.contains("1.2") }, "the version inside is not the tag")
        let notAVersion = OnePercentReleaseCheck.check(zip: zip, tag: "v1.1", configuration: config, checkSignature: false)
        #expect(notAVersion.problems.contains { $0.contains("not a valid version") })
        let unsigned = OnePercentReleaseCheck.check(zip: zip, tag: "1.1", configuration: config, checkSignature: true)
        #expect(unsigned.problems.count == 1, "real signature checks refuse the unsigned fake: \(unsigned.problems)")
    }

    // MARK: - #38

    /// 2026-11-24 (#38): a ZIP made without `--norsrc` passes (OnePercent unpacks it with ditto) but gets a warning.
    @Test func appleDoubleEntriesAreWarnedAbout() throws {
        let root = try Fixture.temporaryRoot("appledouble")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try Fixture.makeApp(root.appendingPathComponent("src/TestApp.app"), version: "1.1", build: "2")
        #expect(Fixture.tool("/usr/bin/xattr", ["-w", "com.example.note", "x", app.appendingPathComponent("Contents/Info.plist").path]) == 0)
        let plain = root.appendingPathComponent("plain/TestApp_1.1.zip")
        let clean = root.appendingPathComponent("clean/TestApp_1.1.zip")
        for folder in [plain, clean] { try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true) }
        #expect(Fixture.zip(app, to: plain))
        #expect(Fixture.tool("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--keepParent", app.path, clean.path]) == 0)
        let warned = OnePercentReleaseCheck.check(zip: plain, tag: "1.1", configuration: Fixture.configuration(), checkSignature: false)
        #expect(warned.problems.isEmpty, "\(warned.problems)")
        #expect(warned.warnings.count == 1 && warned.warnings[0].contains("--norsrc"), "\(warned.warnings)")
        let quiet = OnePercentReleaseCheck.check(zip: clean, tag: "1.1", configuration: Fixture.configuration(), checkSignature: false)
        #expect(quiet.problems.isEmpty && quiet.warnings.isEmpty, "\(quiet.warnings)")
    }

    /// The minimum macOS and processors of the app in the ZIP are reported — raising them is never a surprise.
    @Test func reportsWhatTheAppNeeds() throws {
        let root = try Fixture.temporaryRoot("facts")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try Fixture.makeApp(root.appendingPathComponent("src/TestApp.app"), version: "1.1", build: "2",
                                      extraInfo: ["LSMinimumSystemVersion": "15.0", "CFBundleExecutable": Fixture.appName])
        let executable = app.appendingPathComponent("Contents/MacOS/\(Fixture.appName)")
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        let zip = root.appendingPathComponent("TestApp_1.1.zip")
        #expect(Fixture.zip(app, to: zip))
        let report = OnePercentReleaseCheck.check(zip: zip, tag: "1.1", configuration: Fixture.configuration(), checkSignature: false)
        #expect(report.problems.isEmpty, "\(report.problems)")
        #expect(report.minimumSystemVersion == "15.0" && report.tag == "1.1")
        #expect(!report.architectures.isEmpty && report.architectures.allSatisfy { $0 == "arm64" || $0 == "x86_64" }, "\(report.architectures)")
        #expect(OnePercentReleaseCheck.architectureName(0x12) == "cpu type 0x00000012")
    }
}

/// 2026-11-20 (리뷰 P3-22): 표시 판단 표 — 예전엔 `installRechecksFirst`·`showsMenuNotice` 시험이 없었다.
@Suite struct PresentationTests {
    let update = AvailableUpdate(tag: "1.1", version: "1.1",
                                 asset: ReleaseAsset(name: "TestApp_1.1.zip", downloadURL: URL(string: "https://github.com/x")!, size: 1))

    @Test func resolveTable() {
        func p(_ phase: OnePercentUpdater.Phase, error: OnePercentError? = nil, stored: Bool = false) -> UpdateStatusPresentation {
            .resolve(phase: phase, error: error, storedLatestIsNewer: stored)
        }
        #expect(p(.available(update)) == UpdateStatusPresentation(line: .newVersion, showsInstallButton: true, showsMenuNotice: true))
        #expect(p(.available(update), error: .httpStatus(500)).error == .httpStatus(500) && p(.available(update), error: .httpStatus(500)).showsInstallButton)
        #expect(p(.idle, stored: true) == UpdateStatusPresentation(line: .newVersion, showsInstallButton: true, installRechecksFirst: true, showsMenuNotice: true))
        #expect(p(.idle) == UpdateStatusPresentation(line: .none) && p(.upToDate, stored: true) == UpdateStatusPresentation(line: .none))
        #expect(p(.checking) == UpdateStatusPresentation(line: .checking))
        #expect(p(.downloading(fraction: 0.5)) == UpdateStatusPresentation(line: .downloading(fraction: 0.5), showsCancelButton: true))
        #expect(p(.verifying) == UpdateStatusPresentation(line: .verifying, showsCancelButton: true))
        #expect(p(.installing) == UpdateStatusPresentation(line: .installing))
    }

    @Test func cancelIsNotAnError() {
        let cancelled = UpdateStatusPresentation(line: .none, error: .cancelled)
        #expect(cancelled.errorText == OnePercentError.cancelled.localizedDescription)
        let failed = UpdateStatusPresentation(line: .none, error: .rateLimited)
        #expect(failed.errorText == OnePercentText.error(.rateLimited) && failed.errorText != OnePercentError.rateLimited.localizedDescription)
    }
}
