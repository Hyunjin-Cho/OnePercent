import Foundation

/// One entry of a ZIP's central directory.
struct ZipEntry: Equatable, Sendable {
    let name: String
    let uncompressedSize: UInt64
    /// The entry is a symbolic link (Unix mode in the external attributes).
    let isSymbolicLink: Bool

    init(name: String, uncompressedSize: UInt64, isSymbolicLink: Bool = false) {
        self.name = name
        self.uncompressedSize = uncompressedSize
        self.isSymbolicLink = isSymbolicLink
    }
}

struct ZipDirectoryLocation: Equatable, Sendable {
    let entries: Int
    let size: Int
    let offset: Int
}

/// Why an archive was refused. Shown to the user, so every case has a localized message.
public enum ArchiveProblem: Equatable, Sendable {
    case unreadableListing
    case empty
    case tooManyEntries(count: Int, max: Int)
    case tooLarge(maxMB: UInt64)
    case outsideApp(appFolder: String)
    case linkedEntry(appFolder: String)
    case unexpectedTopLevel(appFolder: String, count: Int)
    case extractedTooLarge(maxMB: UInt64)
    case extractedTooManyItems(max: Int)
    case extractionTimedOut(seconds: Int)
    case escapingLink(appFolder: String)
    case missingApp(appFolder: String)
}

/// Reads a ZIP's central directory directly and judges it **before** unpacking (no reliance on a tool's output format).
///
/// ⚠️ The sizes a ZIP declares cannot be trusted — 2026-11-13 (하늘키보드) 실측: 1,000바이트로 적힌 항목을 `ditto -x -k` 가
/// 64MiB 끝까지 풀었다. So this listing check is a first gate for honest large files and odd paths; the real limits are
/// enforced on disk while unpacking (``extractionProblem(bytes:items:elapsed:limits:)``).
/// ⚠️ Names cannot be trusted either — `ditto -x -k` unpacks by each file's local header name, not the central listing.
/// A ZIP can list a name inside the app and unpack to a different one, so the top level is checked again after unpacking.
/// Release ZIPs made with `ditto -c -k --keepParent` have no comment, no ZIP64, and every entry under `<appName>.app/`.
/// Anything else is refused (fail-closed).
enum UpdateArchive {
    /// Bytes read from the end: the end record (22 bytes) and a possible ZIP64 locator in front of it (20 bytes).
    static let tailBytes = 64
    /// Most central-directory bytes read. A 221-entry release had 28,193 bytes.
    static let maxDirectoryBytes = 4 * 1024 * 1024

    private static func u16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
    private static func signature(_ b: [UInt8], _ i: Int, _ third: UInt8, _ fourth: UInt8) -> Bool {
        i >= 0 && i + 4 <= b.count && b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == third && b[i + 3] == fourth
    }

    /// The central directory's location from the end record. `nil` for a comment, multiple disks, ZIP64,
    /// or a directory that does not sit right before the end record.
    static func directoryLocation(tail: [UInt8], fileSize: Int) -> ZipDirectoryLocation? {
        guard tail.count >= 22, tail.count <= fileSize else { return nil }
        let index = tail.count - 22
        guard signature(tail, index, 0x05, 0x06), u16(tail, index + 20) == 0 else { return nil }
        if signature(tail, index - 20, 0x06, 0x07) { return nil }
        let disk = u16(tail, index + 4), directoryDisk = u16(tail, index + 6)
        let onDisk = u16(tail, index + 8), total = u16(tail, index + 10)
        let size = u32(tail, index + 12), offset = u32(tail, index + 16)
        guard disk == 0, directoryDisk == 0, onDisk == total, total != 0xffff,
              size != 0xffff_ffff, offset != 0xffff_ffff, Int(size) <= maxDirectoryBytes,
              Int(offset) + Int(size) == fileSize - 22 else { return nil }
        return ZipDirectoryLocation(entries: total, size: Int(size), offset: Int(offset))
    }

    /// Entry names, declared sizes and link flags. `nil` when the format is off (signature, lengths, UTF-8),
    /// ZIP64 markers are present, or bytes are left over.
    static func entries(centralDirectory d: [UInt8], expectedCount: Int) -> [ZipEntry]? {
        var result: [ZipEntry] = []
        var position = 0
        for _ in 0..<expectedCount {
            guard position + 46 <= d.count, signature(d, position, 0x01, 0x02) else { return nil }
            let compressed = u32(d, position + 20), size = u32(d, position + 24)
            let nameLength = u16(d, position + 28)
            let external = u32(d, position + 38)
            let next = position + 46 + nameLength + u16(d, position + 30) + u16(d, position + 32)
            guard compressed != 0xffff_ffff, size != 0xffff_ffff, u16(d, position + 34) == 0,
                  nameLength > 0, next <= d.count,
                  let name = String(bytes: d[(position + 46)..<(position + 46 + nameLength)], encoding: .utf8) else { return nil }
            // 2026-11-20 (Fable 리뷰 — 안쪽 링크 방어 한 겹 더): 바깥 속성의 위 16비트가 Unix 파일 종류다. 링크(0o120000)면 표시한다.
            // 만든 OS 칸(Unix=3, OS X=19)과 상관없이 본다 — 엄격한 쪽으로 닫는다.
            let mode = external >> 16
            result.append(ZipEntry(name: name, uncompressedSize: UInt64(size), isSymbolicLink: mode & 0o170000 == 0o120000))
            position = next
        }
        return position == d.count ? result : nil
    }

    /// A plain relative path under `<appFolder>/` — no `..`, `.`, empty parts, backslashes or NUL. A trailing `/` is allowed.
    /// 2026-11-20 (PR #1 보안 리뷰 P3-2): 바이트로 자른다. Swift 글자(Character) 단위로 자르면 `/` 뒤의 결합 문자·앞의 U+0600 이
    /// `..` 마디를 한 글자로 묶어 숨겼다.
    static func isInsideApp(_ name: String, appFolder: String) -> Bool {
        let bytes = Array(name.utf8)
        guard bytes.starts(with: Array((appFolder + "/").utf8)), !bytes.contains(0x5C), !bytes.contains(0) else { return false }
        let parts = bytes.split(separator: 0x2F, omittingEmptySubsequences: false)
        for (index, part) in parts.enumerated() {
            if part.isEmpty { if index == parts.count - 1 { continue }; return false }
            if part.elementsEqual([0x2E]) || part.elementsEqual([0x2E, 0x2E]) { return false }
        }
        return true
    }

    /// The listing check before unpacking. `nil` means it may be unpacked.
    static func problem(_ entries: [ZipEntry], limits: ArchiveLimits, appFolder: String) -> ArchiveProblem? {
        guard !entries.isEmpty else { return .empty }
        guard entries.count <= limits.entries else { return .tooManyEntries(count: entries.count, max: limits.entries) }
        var total: UInt64 = 0
        var links: [String] = []
        for entry in entries {
            let (sum, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, sum <= limits.bytes else { return .tooLarge(maxMB: limits.bytes / 1024 / 1024) }
            total = sum
            guard isInsideApp(entry.name, appFolder: appFolder) else { return .outsideApp(appFolder: appFolder) }
            if entry.isSymbolicLink {
                var name = entry.name
                while name.hasSuffix("/") { name.removeLast() }
                links.append(name)
            }
        }
        // 2026-11-20 (Fable 리뷰): 링크 항목 "아래"에 다른 항목이 있으면 그 항목은 링크를 따라 앱 밖에 써질 수 있다.
        // 실측(macOS 27.2.1): 지금 ditto 는 "Not a directory" 로 멈추지만, 도구의 동작에 기대지 않고 목록 단계에서 거부한다.
        // 링크 자체는 막지 않는다 — 프레임워크 번들(Versions/Current → A)에 정상으로 들어 있다.
        // 2026-11-20 (보안 리뷰 P3-4): 항목마다 조상 경로를 링크 집합에서 찾는다(예전엔 링크 × 항목, 제곱 시간).
        let linkSet = Set(links)
        if !linkSet.isEmpty {
            for entry in entries {
                var ancestor = Substring(entry.name)
                while ancestor.hasSuffix("/") { ancestor = ancestor.dropLast() }
                while let slash = ancestor.lastIndex(of: "/") {
                    ancestor = ancestor[..<slash]
                    if linkSet.contains(String(ancestor)) { return .linkedEntry(appFolder: appFolder) }
                }
            }
        }
        return nil
    }

    /// After unpacking: the extraction folder must hold exactly `<appFolder>` (hidden files count). `nil` means fine.
    /// 2026-11-13 (하늘키보드 #226 P3-5): 목록 이름과 머리글 이름이 다른 ZIP 을 여기서 거른다.
    static func extractedTopLevelProblem(_ names: [String], appFolder: String) -> ArchiveProblem? {
        names == [appFolder] ? nil : .unexpectedTopLevel(appFolder: appFolder, count: names.count)
    }

    /// While unpacking: stop as soon as bytes on disk, item count or elapsed time passes a limit.
    static func extractionProblem(bytes: UInt64, items: Int, elapsed: TimeInterval, limits: ArchiveLimits) -> ArchiveProblem? {
        if bytes > limits.bytes { return .extractedTooLarge(maxMB: limits.bytes / 1024 / 1024) }
        if items > limits.entries { return .extractedTooManyItems(max: limits.entries) }
        if elapsed > limits.seconds { return .extractionTimedOut(seconds: Int(limits.seconds)) }
        return nil
    }

    /// Symbolic links inside the extracted app that point outside it (or are absolute). Their paths relative to the app.
    /// `codesign --strict` and `kSecCSRestrictSymlinks` also refuse such links; this is a second, independent check.
    ///
    /// 2026-11-20: 경로는 글자만으로 계산한다. `NSString.standardizingPath` 는 그 경로가 있으면 `/private` 머리를 떼고,
    /// 대상이 없는 링크면 그대로 둬서 같은 폴더 안에서도 비교가 어긋났다(시험에서 잡힘).
    /// Every link is checked on its own, so a chain of links can only stay inside if each hop does.
    static func escapingLinks(in app: URL) -> [String] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: app.path) else { return ["?"] }
        var escaping: [String] = []
        while let relative = walker.nextObject() as? String {
            let full = app.appendingPathComponent(relative).path
            // lstat — 링크 자체를 본다. `attributesOfItem` 은 대상이 있는 링크를 따라가 폴더로 읽었다(시험에서 잡힘).
            var info = stat()
            guard lstat(full, &info) == 0, info.st_mode & S_IFMT == S_IFLNK else { continue }
            // 탐색은 링크를 따라 내려가지 않는다(2026-11-20 실측: /etc 를 가리키는 링크가 있어도 항목 5개).
            // `skipDescendants()` 는 부르지 않는다 — 링크에서 부르면 링크가 든 폴더의 나머지를 통째로 건너뛰었다(시험에서 잡힘).
            guard let destination = try? fm.destinationOfSymbolicLink(atPath: full),
                  staysInside(linkAt: relative, destination: destination) else {
                escaping.append("/" + relative)
                if escaping.count >= 20 { break }
                continue
            }
        }
        return escaping
    }

    /// Lexical check: does `destination`, read from the link's folder, stay within the app root?
    /// 2026-11-20 (PR #1 보안 리뷰 P3-1): `..` 는 맨 앞에만 허용한다. 중간의 `..` 는 그 앞 마디가 링크일 때 글자 계산과 실제
    /// 해석이 어긋난다(`a/b/c/s -> ../../..` 를 지나는 `a/b/c/s/../../../victim`). 바이트로 자른다(P3-2).
    static func staysInside(linkAt relative: String, destination: String) -> Bool {
        let target = Array(destination.utf8)
        guard !target.isEmpty, target.first != 0x2F, !target.contains(0) else { return false }
        var stack = Array(relative.utf8).split(separator: 0x2F).dropLast().map(Array.init)
        var seenName = false
        for part in target.split(separator: 0x2F, omittingEmptySubsequences: true) {
            if part.elementsEqual([0x2E]) { continue }
            if part.elementsEqual([0x2E, 0x2E]) {
                guard !seenName, !stack.isEmpty else { return false }
                stack.removeLast()
            } else {
                seenName = true
                stack.append(Array(part))
            }
        }
        return true
    }
}
