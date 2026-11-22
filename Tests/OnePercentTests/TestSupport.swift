import Foundation
@testable import OnePercent

/// In-memory store — tests never write to `~/Library/Preferences`.
/// 2026-11-20: 하늘키보드 시험은 UserDefaults 도메인을 써서 빈 plist 가 1,512개 쌓인 적이 있다(2026-11-13 #226 F-5). 여기선 메모리만 쓴다.
final class MemoryStore: OnePercentStore, @unchecked Sendable {
    private var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    var keys: Set<String> { Set(values.keys) }
}

enum Fixture {
    static let repository = "owner/TestApp"
    static let team = "ABCDE12345"
    static let bundleID = "com.example.testapp"
    static let appName = "TestApp"

    static func configuration(scheme: VersionScheme = .numeric, tagPrefix: String = "", schedule: CheckSchedule = .monthly,
                              location: InstallLocation = .inPlace, requireBuildIncrease: Bool = true,
                              suffixKey: String? = nil) -> OnePercentConfiguration {
        OnePercentConfiguration(repository: repository, teamIdentifier: team, bundleIdentifier: bundleID, appName: appName,
                                versionScheme: scheme, tagPrefix: tagPrefix, versionSuffixInfoKey: suffixKey,
                                requireBuildIncrease: requireBuildIncrease, schedule: schedule, installLocation: location)
    }

    /// A temporary folder at its real path (`/var` → `/private/var`); the admin script refuses linked ancestors.
    static func temporaryRoot(_ name: String) throws -> URL {
        guard let resolved = realpath(FileManager.default.temporaryDirectory.path, nil) else { throw CocoaError(.fileNoSuchFile) }
        defer { free(resolved) }
        let url = URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent("onepercent-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A fake (unsigned) app bundle with an Info.plist and a marker file in `Contents/MacOS`.
    @discardableResult
    static func makeApp(_ url: URL, version: String, build: String, identifier: String = bundleID, marker: String = "code",
                        extraInfo: [String: Any] = [:], payload: Int = 0) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
                                   "CFBundleVersion": build, "CFBundlePackageType": "APPL"]
        info.merge(extraInfo) { _, new in new }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        try Data(marker.utf8).write(to: url.appendingPathComponent("Contents/MacOS/\(appName)"))
        if payload > 0 { try Data(count: payload).write(to: url.appendingPathComponent("Contents/payload")) }
        return url
    }

    static func marker(_ app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/MacOS/\(appName)"), encoding: .utf8)
    }

    @discardableResult
    static func tool(_ executable: String, _ arguments: [String], in directory: URL? = nil) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        if let directory { task.currentDirectoryURL = directory }
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return -1 }
        task.waitUntilExit()
        return task.terminationStatus
    }

    /// The same command a release script uses: `ditto -c -k --keepParent`.
    static func zip(_ app: URL, to zip: URL) -> Bool {
        tool("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path]) == 0
    }

    /// A fake central directory and end record (no file data) — for listing decisions only.
    static func zipBytes(_ entries: [(String, UInt32)], links: Set<String> = [], zip64: Bool = false,
                         comment: [UInt8] = [], trailing: [UInt8] = []) -> [UInt8] {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
        func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xff) } }
        var data: [UInt8] = Array("local data".utf8)
        var directory: [UInt8] = []
        for (name, size) in entries {
            let bytes = Array(name.utf8)
            let mode: UInt32 = links.contains(name) ? 0o120755 : (name.hasSuffix("/") ? 0o40755 : 0o100644)
            directory += join([0x50, 0x4b, 0x01, 0x02], le16(0x0314), le16(20), le16(0x0800), le16(8), le16(0), le16(0))
            directory += join(le32(0), le32(zip64 ? 0xffff_ffff : size / 2), le32(zip64 ? 0xffff_ffff : size))
            directory += join(le16(bytes.count), le16(0), le16(0), le16(0), le16(0), le32(mode << 16), le32(0), bytes)
        }
        directory += trailing
        let offset = UInt32(data.count)
        data += directory
        data += join([0x50, 0x4b, 0x05, 0x06], le16(0), le16(0), le16(entries.count), le16(entries.count))
        data += join(le32(UInt32(directory.count)), le32(offset), le16(comment.count), comment)
        return data
    }

    /// The parts one after another. 2026-11-22 (#10): Swift 6.0(Xcode 16.0)은 배열 글자와 `+` 를 길게 이은 식을
    /// "unable to type-check this expression in reasonable time" 으로 포기했다. 이어 붙이기를 함수 하나로 한다.
    static func join(_ parts: [UInt8]...) -> [UInt8] { parts.flatMap { $0 } }

    static func parse(_ bytes: [UInt8]) -> [ZipEntry]? {
        let tail = Array(bytes.suffix(UpdateArchive.tailBytes))
        guard let location = UpdateArchive.directoryLocation(tail: tail, fileSize: bytes.count),
              location.offset + location.size <= bytes.count else { return nil }
        return UpdateArchive.entries(centralDirectory: Array(bytes[location.offset..<(location.offset + location.size)]),
                                     expectedCount: location.entries)
    }

    /// A stored (uncompressed) ZIP whose central names may differ from the local header names.
    /// 2026-11-13 (하늘키보드 #226 P3-5): 리뷰어 zipcraft 17번과 같은 꼴.
    static func craftedZip(_ entries: [(local: String, central: String, data: Data)]) -> Data {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
        func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xff) } }
        func crc32(_ bytes: [UInt8]) -> UInt32 {
            var c: UInt32 = 0xffff_ffff
            for b in bytes { c ^= UInt32(b); for _ in 0..<8 { c = (c >> 1) ^ (0xEDB8_8320 & (0 &- (c & 1))) } }
            return ~c
        }
        var body: [UInt8] = [], central: [UInt8] = []
        for entry in entries {
            let local = Array(entry.local.utf8), name = Array(entry.central.utf8), data = [UInt8](entry.data)
            let crc = crc32(data), size = UInt32(data.count), offset = UInt32(body.count)
            body += le32(0x0403_4b50) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            body += le32(crc) + le32(size) + le32(size) + le16(local.count) + le16(0) + local + data
            let mode: UInt32 = entry.central.hasSuffix("/") ? 0o40755 : 0o100644
            central += le32(0x0201_4b50) + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            central += le32(crc) + le32(size) + le32(size) + le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(mode << 16) + le32(offset) + name
        }
        let directoryOffset = UInt32(body.count)
        body += central
        body += le32(0x0605_4b50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count) + le32(UInt32(central.count)) + le32(directoryOffset) + le16(0)
        return Data(body)
    }

    /// Rewrites every declared uncompressed size (central and local) to 1 byte.
    static func understate(_ url: URL) -> Bool {
        guard var bytes = try? [UInt8](Data(contentsOf: url)) else { return false }
        let tail = Array(bytes.suffix(UpdateArchive.tailBytes))
        guard let location = UpdateArchive.directoryLocation(tail: tail, fileSize: bytes.count) else { return false }
        func put32(_ value: UInt32, at index: Int) { for i in 0..<4 { bytes[index + i] = UInt8((value >> (8 * UInt32(i))) & 0xff) } }
        func get16(_ index: Int) -> Int { Int(bytes[index]) | Int(bytes[index + 1]) << 8 }
        func get32(_ index: Int) -> Int { (0..<4).reduce(0) { $0 | Int(bytes[index + $1]) << (8 * $1) } }
        var position = location.offset
        for _ in 0..<location.entries {
            let local = get32(position + 42)
            if get32(position + 24) > 1 {
                put32(1, at: position + 24)
                if get32(local + 22) > 1 { put32(1, at: local + 22) }
            }
            position += 46 + get16(position + 28) + get16(position + 30) + get16(position + 32)
        }
        return (try? Data(bytes).write(to: url)) != nil
    }
}

extension BundleChecks {
    /// Every Apple-signature check passes (fake bundles have no signature). The rest of the pipeline runs for real.
    static let accepting = BundleChecks(signedByTeam: { _, _ in true }, codesignValid: { _, _ in true }, notarizationAccepted: { _ in true })
}

/// Thread-safe call log for closures that run off the main actor.
final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ value: String) { lock.withLock { items.append(value) } }
    var all: [String] { lock.withLock { items } }
}
