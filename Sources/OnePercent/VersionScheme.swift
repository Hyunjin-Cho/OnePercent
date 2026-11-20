import Foundation

/// How OnePercent reads and orders version strings.
///
/// A scheme turns a version string into a list of numbers that can be compared part by part.
/// Missing trailing parts count as zero, so with `.numeric` the versions `1`, `1.0` and `1.0.0` are the same.
/// A string the scheme cannot read is never treated as newer — the update is simply not offered (fail-closed).
///
/// Built-in schemes:
/// - ``numeric``: `1`, `1.0`, `1.2.3`, `2026.11.17` — one to four parts of digits.
/// - ``calendar(hotfixMarker:)``: dated releases such as `2026.11.17`, optionally with a numbered hotfix suffix
///   such as `2026.11.17_hotfix2`.
/// - Your own: `VersionScheme(name:key:)` with any parsing rule that returns comparable numbers.
///
/// 2026-11-20: 하늘키보드의 날짜형(CalVer) 고정 규칙을 앱이 고를 수 있게 일반화했다(오너: "사용자가 원하는 걸 할 수 있게 자유롭게").
public struct VersionScheme: Sendable {
    /// Shown in logs and diagnostics only.
    public let name: String
    private let makeKey: @Sendable (String) -> [Int]?

    /// - Parameters:
    ///   - name: A label for logs.
    ///   - key: Returns the comparable numbers for a version string, or `nil` when the string is not a valid version.
    ///     Return the same numbers for strings that mean the same version.
    public init(name: String, key: @escaping @Sendable (String) -> [Int]?) {
        self.name = name
        self.makeKey = key
    }

    /// The comparable numbers for `text`, or `nil` when the scheme cannot read it.
    public func key(_ text: String) -> [Int]? { makeKey(text) }

    public func isValid(_ text: String) -> Bool { key(text) != nil }

    /// Orders two versions. `nil` when either one is not valid in this scheme.
    public func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        guard let left = key(lhs), let right = key(rhs) else { return nil }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    /// `true` only when both are valid and `candidate` is strictly newer than `current`.
    public func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(current, candidate) == .orderedAscending
    }

    /// `true` only when both are valid and mean the same version.
    public func isSame(_ lhs: String, _ rhs: String) -> Bool {
        compare(lhs, rhs) == .orderedSame
    }
}

// MARK: - Built-in schemes

extension VersionScheme {
    /// Numbers separated by dots — `1`, `1.0`, `1.2.3`, `2026.11.17`.
    /// One to four parts; each part is 1–9 ASCII digits. Anything else (a leading `v`, letters, empty parts) is invalid.
    public static let numeric = VersionScheme(name: "numeric") { text in
        numericParts(text, allowedCounts: 1...4, maxDigits: 9)
    }

    /// Dated releases: `YYYY.MM.DD`, plus an optional numbered hotfix suffix (`2026.11.17_hotfix1` … `_hotfix999`).
    /// Two-part numbers (`2026.8`) are accepted too so older builds still compare.
    /// A suffixed version must be a real calendar date. A bare marker (`_hotfix`), `_hotfix0` and leading zeros are invalid.
    /// Order: date first, then the hotfix number as a number (`_hotfix9` < `_hotfix10`).
    ///
    /// 2026-11-20: 하늘키보드 `CalVer`(2026-11-04 #131 번호 붙은 핫픽스)와 같은 규칙이다.
    public static func calendar(hotfixMarker: String = "_hotfix") -> VersionScheme {
        VersionScheme(name: "calendar") { text in
            var numeric = Substring(text)
            var hotfix = 0
            if !hotfixMarker.isEmpty, let marker = text.range(of: hotfixMarker) {
                let digits = text[marker.upperBound...]
                guard (1...3).contains(digits.count), digits.first != "0",
                      digits.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(digits) else { return nil }
                hotfix = number
                numeric = text[..<marker.lowerBound]
            }
            let pieces = numeric.split(separator: ".", omittingEmptySubsequences: false)
            guard let parts = numericParts(String(numeric), allowedCounts: 2...3, maxDigits: 6) else { return nil }
            if hotfix > 0 {
                guard parts.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
                      isCalendarDate(year: parts[0], month: parts[1], day: parts[2]) else { return nil }
            }
            return [parts[0], parts[1], parts.count == 3 ? parts[2] : 0, hotfix]
        }
    }

    static func numericParts(_ text: String, allowedCounts: ClosedRange<Int>, maxDigits: Int) -> [Int]? {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard allowedCounts.contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.count <= maxDigits,
                  piece.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(piece) else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    static func isCalendarDate(year: Int, month: Int, day: Int) -> Bool {
        guard year > 0, (1...12).contains(month), (1...31).contains(day) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }
}
