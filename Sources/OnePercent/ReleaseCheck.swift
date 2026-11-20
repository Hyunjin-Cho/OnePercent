import Foundation

/// Checks a release ZIP **before** you upload it, with the same code the updater runs on users' Macs.
/// 2026-11-20: 하늘키보드 `scripts/check_update_zip.swift` 와 같은 생각 — ZIP 만드는 방법이 바뀌어 현장 업데이트가 거부되는 일을
/// 빌드 단계에서 막는다. 서명·공증 검사는 실제 앱으로 함께 돌린다(`checkSignature`).
public enum OnePercentReleaseCheck {
    public struct Report: Sendable {
        /// Problems, as localized sentences. Empty means the ZIP would be accepted.
        public let problems: [String]
        /// The public version read from the app inside the ZIP.
        public let bundleVersion: String?
        public let build: String?
    }

    /// - Parameters:
    ///   - zip: The release asset.
    ///   - tag: The release tag it will be attached to. The asset name, the version and the tag must agree.
    ///   - checkSignature: Also run the Developer ID, `codesign --deep --strict` and notarization checks (needs the real, notarized app).
    public static func check(zip: URL, tag: String, configuration: OnePercentConfiguration, checkSignature: Bool = true) -> Report {
        let table = L10n.current
        var problems = configuration.problems
        if zip.lastPathComponent != configuration.assetFileName(forTag: tag) {
            problems.append("asset name must be \(configuration.assetFileName(forTag: tag)), not \(zip.lastPathComponent)")
        }
        guard let version = ReleaseDecision.version(fromTag: tag, configuration: configuration) else {
            return Report(problems: problems + ["tag \(tag) is not a valid version for scheme \(configuration.versionScheme.name)"],
                          bundleVersion: nil, build: nil)
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("OnePercent-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            // 현재 버전을 "0" 으로 두면 버전·빌드 상승 검사는 거의 항상 통과한다 — 여기선 꼴과 서명, 태그 일치를 본다.
            let input = UpdateVerifier.Input(zip: zip, workDir: work, configuration: configuration,
                                             currentVersion: "0", currentBuild: "0", releaseVersion: version)
            let checks = checkSignature ? BundleChecks.live : BundleChecks(signedByTeam: { _, _ in true }, codesignValid: { _, _ in true },
                                                                         notarizationAccepted: { _ in true })
            let verified = try UpdateVerifier.extractAndVerify(input, checks: checks)
            return Report(problems: problems, bundleVersion: verified.identity.version, build: verified.identity.build)
        } catch let error as OnePercentError {
            return Report(problems: problems + [error.message(table)], bundleVersion: nil, build: nil)
        } catch {
            return Report(problems: problems + [error.localizedDescription], bundleVersion: nil, build: nil)
        }
    }
}
