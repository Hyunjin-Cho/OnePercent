import Foundation
import Testing
@testable import OnePercent

/// 2026-11-24 (#33): a new version this Mac cannot open (minimum macOS, processor) is never put in place.
@Suite struct CompatibilityTests {
    static let arm = NSBundleExecutableArchitectureARM64
    static let intel = NSBundleExecutableArchitectureX86_64

    func mac(_ version: [Int] = [27, 2, 1], runs runnable: Set<Int> = [arm], appHas architectures: [Int]? = nil) -> SystemProfile {
        SystemProfile(version: version, runnableArchitectures: runnable, architectures: { _ in architectures })
    }

    let app = URL(fileURLWithPath: "/nonexistent/TestApp.app")

    @Test func versionRules() {
        #expect(Compatibility.parseVersion("14") == [14])
        #expect(Compatibility.parseVersion(" 10.15.7 ") == [10, 15, 7])
        for bad in ["", "abc", "14.", ".14", "14..1", "14.0-beta", "1.2.3.4.5", "١٤"] {
            #expect(Compatibility.parseVersion(bad) == nil, "\(bad)")
        }
        #expect(Compatibility.isAtLeast([27, 2, 1], [27]))
        #expect(Compatibility.isAtLeast([27, 2, 1], [27, 2, 1]))
        #expect(!Compatibility.isAtLeast([27, 2, 1], [27, 3]))
        #expect(!Compatibility.isAtLeast([27], [27, 0, 1]))
        #expect(Compatibility.isAtLeast([28, 0, 0], [27, 9, 9]))
        #expect(Compatibility.display([28, 0, 0]) == "28.0" && Compatibility.display([27, 2, 1]) == "27.2.1" && Compatibility.display([14, 0]) == "14.0")
    }

    @Test func minimumSystem() {
        #expect(Compatibility.problem(info: ["LSMinimumSystemVersion": "28.0"], app: app, version: "1.9", system: mac())
                == .requiresNewerSystem(version: "1.9", minimum: "28.0", running: "27.2.1"))
        #expect(Compatibility.problem(info: ["LSMinimumSystemVersion": "27.2.1"], app: app, version: "1.9", system: mac()) == nil, "equal is enough")
        #expect(Compatibility.problem(info: ["LSMinimumSystemVersion": "14.0"], app: app, version: "1.9", system: mac()) == nil)
        #expect(Compatibility.problem(info: ["LSMinimumSystemVersion": "soon"], app: app, version: "1.9", system: mac()) == nil,
                "an unreadable requirement is no requirement (macOS does the same)")
        #expect(Compatibility.problem(info: ["LSMinimumSystemVersion": 28], app: app, version: "1.9", system: mac()) == nil, "not text")
        #expect(Compatibility.problem(info: nil, app: app, version: "1.9", system: mac()) == nil)
    }

    @Test func processors() {
        #expect(Compatibility.problem(info: [:], app: app, version: "1.9", system: mac(appHas: [Self.intel])) == .unsupportedProcessor(version: "1.9"),
                "an Apple silicon app running natively does not take an Intel-only update")
        #expect(Compatibility.problem(info: [:], app: app, version: "1.9", system: mac(runs: [Self.arm, Self.intel], appHas: [Self.intel])) == nil,
                "an Intel app running under Rosetta keeps working as it does now")
        #expect(Compatibility.problem(info: [:], app: app, version: "1.9", system: mac(runs: [Self.intel], appHas: [Self.arm])) == .unsupportedProcessor(version: "1.9"),
                "an Intel Mac does not take an Apple-silicon-only update")
        #expect(Compatibility.problem(info: [:], app: app, version: "1.9", system: mac(appHas: [Self.arm, Self.intel])) == nil, "universal")
        #expect(Compatibility.problem(info: [:], app: app, version: "1.9", system: mac(appHas: nil)) == nil, "unreadable: the signature check judged it")
        #expect(Compatibility.problem(info: [:], app: app, version: "1.9", system: mac(appHas: [])) == nil)
        #expect(Compatibility.problem(info: ["LSMinimumSystemVersion": "99"], app: app, version: "1.9", system: mac(appHas: [Self.intel]))
                == .requiresNewerSystem(version: "1.9", minimum: "99", running: "27.2.1"), "macOS is named first")
    }

    /// On this Mac, with a real executable: the architectures are read and this Mac can run them.
    @Test func thisMacReadsARealExecutable() throws {
        let root = try Fixture.temporaryRoot("arch")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = try Fixture.makeApp(root.appendingPathComponent("TestApp.app"), version: "1.1", build: "2",
                                       extraInfo: ["CFBundleExecutable": Fixture.appName])
        let executable = real.appendingPathComponent("Contents/MacOS/\(Fixture.appName)")
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        let system = SystemProfile.current
        let architectures = try #require(system.architectures(real), "a Mach-O executable has readable architectures")
        #expect(!architectures.isEmpty && !system.runnableArchitectures.isDisjoint(with: architectures), "\(architectures)")
        #expect(system.runnableArchitectures.contains(SystemProfile.machineArchitecture))
        #expect(system.version.first ?? 0 >= 14, "\(system.version)")
        #expect(Compatibility.problem(info: ["LSMinimumSystemVersion": "14.0"], app: real, version: "1.1", system: system) == nil)
    }

    @Test func records() {
        let record = IncompatibleRecord(version: "1.9", minimumSystem: "28.0", runnable: [Self.intel, Self.arm])
        #expect(IncompatibleRecord(stored: record.stored) == record, "survives the store")
        #expect(IncompatibleRecord(stored: ["version": "1.9"]) == nil && IncompatibleRecord(stored: "x") == nil)
        #expect(record.applies(to: mac(runs: [Self.arm, Self.intel])))
        #expect(!record.applies(to: mac([28, 0], runs: [Self.arm, Self.intel])), "macOS was updated")
        #expect(!record.applies(to: mac(runs: [Self.arm])), "another Mac (preferences moved over)")
        let processor = IncompatibleRecord(error: .unsupportedProcessor(version: "1.9"), system: mac())
        #expect(processor?.applies(to: mac([99])) == true && processor?.error(on: mac()) == .unsupportedProcessor(version: "1.9"))
        #expect(IncompatibleRecord(error: .rateLimited, system: mac()) == nil)
        #expect(record.error(on: mac([27, 3])) == .requiresNewerSystem(version: "1.9", minimum: "28.0", running: "27.3"))
    }

    /// The real pipeline (ditto, checks) refuses before anything is installed — and the release checker does not judge
    /// the developer's Mac.
    @Test func thePipelineRefusesAndTheReleaseCheckerDoesNot() throws {
        let root = try Fixture.temporaryRoot("compat-pipeline")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try Fixture.makeApp(root.appendingPathComponent("src/TestApp.app"), version: "1.1", build: "2",
                                         extraInfo: ["LSMinimumSystemVersion": "99.0"])
        let zip = root.appendingPathComponent("TestApp_1.1.zip")
        #expect(Fixture.zip(source, to: zip))
        let work = root.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        var input = UpdateVerifier.Input(zip: zip, workDir: work, configuration: Fixture.configuration(), currentVersion: "1.0",
                                         currentBuild: "1", releaseVersion: "1.1")
        input.system = mac()
        #expect(throws: OnePercentError.requiresNewerSystem(version: "1.1", minimum: "99.0", running: "27.2.1")) {
            try UpdateVerifier.extractAndVerify(input, checks: .accepting)
        }
        let report = OnePercentReleaseCheck.check(zip: zip, tag: "1.1", configuration: Fixture.configuration(), checkSignature: false)
        #expect(report.problems.isEmpty, "\(report.problems)")
    }

    @Test(arguments: LocalizationTests.languages) func messagesRender(_ language: String) {
        let table = L10n.table(language)
        for error in [OnePercentError.requiresNewerSystem(version: "1.9", minimum: "28.0", running: "27.2.1"), .unsupportedProcessor(version: "1.9")] {
            let text = error.message(table)
            #expect(text.contains("1.9") && !text.contains("%") && !text.contains("error."), "\(language): \(text)")
            if case .requiresNewerSystem = error { #expect(text.contains("28.0") && text.contains("27.2.1"), "\(language): \(text)") }
        }
    }
}
