import Foundation
import Testing
@testable import OnePercent

/// 2026-11-20: 하늘키보드 `UpdateInstallTests.archiveDecisions` 를 옮기고, 링크 항목(Fable 리뷰)과 밖을 가리키는 링크 검사를 더했다.
@Suite struct ArchiveTests {
    let app = "TestApp.app/"
    let limits = ArchiveLimits.standard
    var normal: [(String, UInt32)] {
        [(app, 0), (app + "Contents/", 0), (app + "Contents/Info.plist", 900),
         (app + "Contents/._MacOS", 120), (app + "Contents/MacOS/TestApp", 4_000_000)]
    }

    func problem(_ list: [(String, UInt32)], links: Set<String> = [], _ limits: ArchiveLimits = .standard) -> ArchiveProblem? {
        guard let parsed = Fixture.parse(Fixture.zipBytes(list, links: links)) else { return .unreadableListing }
        return UpdateArchive.problem(parsed, limits: limits, appFolder: "TestApp.app")
    }

    @Test func limitsLeaveRoom() {
        // 근거: 하늘키보드 후보 111 실제 ZIP(2026-11-13) — 항목 221개, 풀린 크기 81,828,760바이트, ditto 0.20초.
        // 2026-11-20 실측: Ghostty 1.4.0 ZIP — 항목 2,283개.
        #expect(limits.entries >= 2_283 * 10 && limits.bytes >= 81_828_760 * 5 && limits.seconds >= 0.2 * 100)
        #expect(limits.bytes > UInt64(Limits.standard.maxAssetBytes))
    }

    @Test func readsTheCentralDirectory() {
        let entries = Fixture.parse(Fixture.zipBytes(normal))
        #expect(entries?.count == 5 && entries?.last?.uncompressedSize == 4_000_000)
        #expect(problem(normal) == nil)
        #expect(Fixture.parse(Fixture.zipBytes(normal, comment: Array("note".utf8))) == nil, "comment")
        #expect(Fixture.parse(Fixture.zipBytes(normal, zip64: true)) == nil, "ZIP64")
        #expect(Fixture.parse(Fixture.zipBytes(normal, trailing: [0, 0, 0])) == nil, "trailing bytes")
        #expect(Fixture.parse(Array(Fixture.zipBytes(normal).dropLast(3))) == nil, "cut end record")
        #expect(Fixture.parse(Array("not a zip".utf8)) == nil)
    }

    @Test func refusesPathsOutsideTheApp() {
        for bad in ["../evil", "/abs/TestApp.app/x", "TestApp.app/../../x", "Other.app/Contents/x",
                    "TestApp.appx/y", "__MACOSX/TestApp.app/._x", "TestApp.app/a\\..\\b", "TestApp.app//x", "TestApp.app/./x"] {
            #expect(problem(normal + [(bad, 1)]) == .outsideApp(appFolder: "TestApp.app"), "\(bad)")
        }
    }

    @Test func countAndSizeLimits() {
        #expect(problem([]) == .empty)
        let tight = ArchiveLimits(entries: 2_000, bytes: 512 * 1024 * 1024, seconds: 120)
        let many = (0..<2_001).map { (app + "f\($0)", UInt32(1)) }
        #expect(problem(many, tight) == .tooManyEntries(count: 2_001, max: 2_000))
        #expect(problem(Array(many.prefix(2_000)), tight) == nil)
        let huge = (0..<130).map { (app + "big\($0)", UInt32(4 * 1024 * 1024)) }
        #expect(problem(huge, tight) == .tooLarge(maxMB: 512))
        let declaredHuge = (0..<3).map { (app + "big\($0)", UInt32.max - 1) }
        #expect(problem(declaredHuge) == .tooLarge(maxMB: 2048), "standard limit")
        let small = ArchiveLimits(entries: 3, bytes: 10, seconds: 1)
        #expect(problem([(app + "a", 5), (app + "b", 5)], small) == nil)
        #expect(problem([(app + "a", 6), (app + "b", 5)], small) != nil)
    }

    /// 2026-11-20 (Fable 리뷰): 링크 "아래"의 항목은 목록 단계에서 거부한다. 링크 자체(프레임워크의 Versions/Current)는 허용한다.
    @Test func entriesUnderALinkAreRefused() {
        let framework = app + "Contents/Frameworks/Kit.framework/"
        let legit = normal + [(framework, 0), (framework + "Versions/", 0), (framework + "Versions/A/", 0),
                              (framework + "Versions/A/Kit", 100), (framework + "Versions/Current", 1), (framework + "Kit", 1)]
        #expect(problem(legit, links: [framework + "Versions/Current", framework + "Kit"]) == nil, "framework links are fine")
        let escape = normal + [(app + "Contents/Resources", 1), (app + "Contents/Resources/payload", 100)]
        #expect(problem(escape, links: [app + "Contents/Resources"]) == .linkedEntry(appFolder: "TestApp.app"))
        let entries = Fixture.parse(Fixture.zipBytes(escape, links: [app + "Contents/Resources"]))
        #expect(entries?.first { $0.name == app + "Contents/Resources" }?.isSymbolicLink == true, "mode bits read")
    }

    @Test func topLevelAfterUnpacking() {
        #expect(UpdateArchive.extractedTopLevelProblem(["TestApp.app"], appFolder: "TestApp.app") == nil)
        #expect(UpdateArchive.extractedTopLevelProblem(["TestApp.app", ".hidden"], appFolder: "TestApp.app") != nil)
        #expect(UpdateArchive.extractedTopLevelProblem([], appFolder: "TestApp.app") != nil)
        #expect(UpdateArchive.extractedTopLevelProblem(["Other.app"], appFolder: "TestApp.app") != nil)
    }

    @Test func extractionLimits() {
        let small = ArchiveLimits(entries: 3, bytes: 10, seconds: 1)
        #expect(UpdateArchive.extractionProblem(bytes: 10, items: 3, elapsed: 0.5, limits: small) == nil)
        #expect(UpdateArchive.extractionProblem(bytes: 11, items: 3, elapsed: 0.5, limits: small) != nil)
        #expect(UpdateArchive.extractionProblem(bytes: 1, items: 4, elapsed: 0.5, limits: small) != nil)
        #expect(UpdateArchive.extractionProblem(bytes: 1, items: 1, elapsed: 1.5, limits: small) != nil)
    }

    @Test func linksPointingOutsideTheApp() throws {
        let root = try Fixture.temporaryRoot("links")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let bundle = try Fixture.makeApp(root.appendingPathComponent("TestApp.app"), version: "1.0", build: "1")
        let versions = bundle.appendingPathComponent("Contents/Frameworks/Kit.framework/Versions")
        try fm.createDirectory(at: versions.appendingPathComponent("A"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: versions.appendingPathComponent("Current").path, withDestinationPath: "A")
        #expect(UpdateArchive.escapingLinks(in: bundle).isEmpty, "relative link inside is fine")
        try fm.createSymbolicLink(atPath: bundle.appendingPathComponent("Contents/out").path, withDestinationPath: "../../outside")
        try fm.createSymbolicLink(atPath: bundle.appendingPathComponent("Contents/abs").path, withDestinationPath: "/etc")
        let escaping = UpdateArchive.escapingLinks(in: bundle)
        #expect(Set(escaping) == ["/Contents/out", "/Contents/abs"], "\(escaping)")
    }

    /// 2026-11-20 (보안 리뷰 P3-2): 결합 문자가 `..` 를 한 글자로 묶어도 바이트로 보면 거부한다.
    @Test func combiningCharactersCannotHideDotDot() {
        let hidden = "TestApp.app/a\u{600}/../../\u{301}b"
        #expect(hidden.split(separator: "/").contains("..") == false, "premise: Swift characters hide the .. part")
        #expect(!UpdateArchive.isInsideApp(hidden, appFolder: "TestApp.app"))
        #expect(!UpdateArchive.staysInside(linkAt: "Contents/x", destination: "a\u{600}/../../\u{301}b"))
        #expect(UpdateArchive.isInsideApp("TestApp.app/Contents/Resources/한글 파일.txt", appFolder: "TestApp.app"), "normal non-ASCII names pass")
    }

    /// 2026-11-20 (보안 리뷰 P3-4): 링크가 많아도 목록 검사는 금방 끝난다.
    @Test func manyLinksStayFast() {
        var entries: [ZipEntry] = []
        for i in 0..<8_000 { entries.append(ZipEntry(name: "TestApp.app/l\(i)", uncompressedSize: 1, isSymbolicLink: true)) }
        for i in 0..<8_000 { entries.append(ZipEntry(name: "TestApp.app/d/f\(i)", uncompressedSize: 1)) }
        let started = Date()
        #expect(UpdateArchive.problem(entries, limits: .standard, appFolder: "TestApp.app") == nil)
        #expect(Date().timeIntervalSince(started) < 1, "\(Date().timeIntervalSince(started)) s")
    }

    /// 2026-11-20 (보안 리뷰 P3-3): 폴더의 확장 속성도 디스크 사용량으로 센다.
    @Test func extendedAttributesCount() throws {
        let root = try Fixture.temporaryRoot("xattr")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("TestApp.app/Contents")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let value = [UInt8](repeating: 7, count: 200_000)
        #expect(setxattr(folder.path, "com.example.big", value, value.count, 0, 0) == 0)
        let usage = UpdateVerifier.diskUsage(of: root, stopAfter: 100)
        #expect(usage.bytes >= 200_000, "\(usage.bytes)")
    }

    @Test func lexicalLinkResolution() {
        let inside: [(String, String)] = [("Contents/Frameworks/K.framework/Versions/Current", "A"),
                                          ("Contents/Frameworks/K.framework/K", "Versions/Current/K"),
                                          ("Contents/a", "../Contents/b"), ("Contents/a", "./b"), ("Contents/a", ".."), ("x", ".")]
        for (link, destination) in inside { #expect(UpdateArchive.staysInside(linkAt: link, destination: destination), "\(link) → \(destination)") }
        let outside: [(String, String)] = [("Contents/a", "../.."), ("x", ".."), ("Contents/a", "/Applications"), ("Contents/a", ""),
                                           ("Contents/a", "b/../../../c"),
                                           // 2026-11-20 보안 리뷰 P3-1: 링크 뒤의 `..` (a/b/c/s 가 ../../.. 링크일 때 실제로는 앱 밖)
                                           ("t", "a/b/c/s/../../../victim"), ("Contents/a", "b/../c")]
        for (link, destination) in outside { #expect(!UpdateArchive.staysInside(linkAt: link, destination: destination), "\(link) → \(destination)") }
    }
}
