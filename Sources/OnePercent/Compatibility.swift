import Foundation

/// This Mac, as far as "can the new version run here" goes.
///
/// 2026-11-24 (#33): 예전엔 서명·공증·버전만 맞으면 바꿔 끼웠다. 새 릴리스가 최소 macOS 를 올리거나 이 Mac 의 프로세서를 빼면
/// "업데이트 성공 → 앱이 안 열림"이 됐다. 이 검사는 **그 릴리스보다 앞선 버전 안에** 들어 있어야 효과가 있다.
struct SystemProfile: Sendable {
    /// macOS version, for example `[27, 2, 1]`.
    var version: [Int]
    /// CPU types (`NSBundleExecutableArchitecture…`) a new version may contain and still run here: this Mac's own processor,
    /// and the one this copy of the app runs as — so an Intel app running under Rosetta keeps working the way it does now.
    var runnableArchitectures: Set<Int>
    /// The executable architectures of an app, or `nil` when they cannot be read. Swapped in tests (fixture apps are not Mach-O).
    var architectures: @Sendable (URL) -> [Int]?

    /// The version as people write it: `27.2.1`, or `28.0` for 28.0.0.
    var versionText: String { Compatibility.display(version) }

    static var current: SystemProfile {
        let running = ProcessInfo.processInfo.operatingSystemVersion
        var runnable: Set<Int> = [machineArchitecture]
        #if arch(arm64)
        runnable.insert(NSBundleExecutableArchitectureARM64)
        #elseif arch(x86_64)
        runnable.insert(NSBundleExecutableArchitectureX86_64)
        #endif
        return SystemProfile(version: [running.majorVersion, running.minorVersion, running.patchVersion],
                             runnableArchitectures: runnable,
                             architectures: { Bundle(url: $0)?.executableArchitectures?.map(\.intValue) })
    }

    /// This Mac's own processor — also when this process runs under Rosetta (`hw.optional.arm64` answers for the machine).
    static var machineArchitecture: Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0, value == 1 { return NSBundleExecutableArchitectureARM64 }
        return NSBundleExecutableArchitectureX86_64
    }
}

enum Compatibility {
    /// `14`, `14.0`, `10.15.7` → numbers. `nil` for anything else (then there is no requirement to check — macOS itself
    /// does not refuse an app for an unreadable `LSMinimumSystemVersion`).
    static func parseVersion(_ text: String) -> [Int]? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        return parts.compactMap { Int($0) }
    }

    /// `running` is at least `minimum` (missing parts count as 0).
    static func isAtLeast(_ running: [Int], _ minimum: [Int]) -> Bool {
        for index in 0..<max(running.count, minimum.count) {
            let have = index < running.count ? running[index] : 0
            let need = index < minimum.count ? minimum[index] : 0
            if have != need { return have > need }
        }
        return true
    }

    /// `[27, 2, 1]` → `27.2.1`, `[28, 0, 0]` → `28.0`.
    static func display(_ version: [Int]) -> String {
        var parts = version
        while parts.count > 2, parts.last == 0 { parts.removeLast() }
        return parts.map(String.init).joined(separator: ".")
    }

    /// Why the app at `app` (with Info.plist `info`) cannot run on `system`, or `nil`. `version` is the release version, for the message.
    /// The macOS requirement is judged first; an unreadable architecture list is not a reason to refuse — the code signature
    /// check already refused a broken executable.
    static func problem(info: [String: Any]?, app: URL, version: String, system: SystemProfile) -> OnePercentError? {
        if let text = info?["LSMinimumSystemVersion"] as? String, let minimum = parseVersion(text),
           !isAtLeast(system.version, minimum) {
            return .requiresNewerSystem(version: version, minimum: text.trimmingCharacters(in: .whitespaces), running: system.versionText)
        }
        if let architectures = system.architectures(app), !architectures.isEmpty,
           system.runnableArchitectures.isDisjoint(with: architectures) {
            return .unsupportedProcessor(version: version)
        }
        return nil
    }
}

/// A version this Mac could not run, remembered so checks do not offer it again (#33).
/// Stored as a small dictionary under ``OnePercentUpdater`` 's `incompatibleUpdate` key.
struct IncompatibleRecord: Equatable {
    let version: String
    /// The `LSMinimumSystemVersion` that was too high, or `nil` when the processor was the reason.
    let minimumSystem: String?
    /// The processors that could run here when the record was made — a record moved to another Mac (Migration Assistant
    /// copies preferences) does not apply there.
    let runnable: [Int]

    init(version: String, minimumSystem: String?, runnable: [Int]) {
        self.version = version
        self.minimumSystem = minimumSystem
        self.runnable = runnable.sorted()
    }

    /// The record for an incompatibility error, or `nil` for any other error.
    init?(error: OnePercentError, system: SystemProfile) {
        switch error {
        case .requiresNewerSystem(let version, let minimum, _):
            self.init(version: version, minimumSystem: minimum, runnable: Array(system.runnableArchitectures))
        case .unsupportedProcessor(let version):
            self.init(version: version, minimumSystem: nil, runnable: Array(system.runnableArchitectures))
        default:
            return nil
        }
    }

    init?(stored: Any?) {
        guard let dictionary = stored as? [String: Any], let version = dictionary["version"] as? String,
              let runnable = dictionary["runnable"] as? [Int] else { return nil }
        self.init(version: version, minimumSystem: dictionary["minimumSystem"] as? String, runnable: runnable)
    }

    var stored: [String: Any] {
        var dictionary: [String: Any] = ["version": version, "runnable": runnable]
        if let minimumSystem { dictionary["minimumSystem"] = minimumSystem }
        return dictionary
    }

    /// Still true on `system`: the same processors, and (for a macOS requirement) macOS is still older than it.
    func applies(to system: SystemProfile) -> Bool {
        guard runnable == system.runnableArchitectures.sorted() else { return false }
        guard let minimumSystem else { return true }
        guard let minimum = Compatibility.parseVersion(minimumSystem) else { return false }
        return !Compatibility.isAtLeast(system.version, minimum)
    }

    /// The error to show again on later checks.
    func error(on system: SystemProfile) -> OnePercentError {
        minimumSystem.map { .requiresNewerSystem(version: version, minimum: $0, running: system.versionText) }
            ?? .unsupportedProcessor(version: version)
    }
}
