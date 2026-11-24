import Foundation

/// Checks a release ZIP **before** you upload it, with the same code the updater runs on users' Macs — and with the
/// configuration you pass, so pass your app's own (limits, `assetName`, `requireBuildIncrease`).
/// 2026-11-22 (#20): 코드는 같아도 설정이 기본값이면 '같은 검사'가 아니었다 — 더 엄격한 상한을 쓰는 앱은 여기서 통과하고
/// 사용자 Mac 에서 거부될 수 있었다. CLI 에 설정 옵션을 더하고, 빠져 있던 ZIP 크기(내려받기 상한) 검사를 넣었다.
/// 2026-11-20: 하늘키보드 `scripts/check_update_zip.swift` 와 같은 생각 — ZIP 만드는 방법이 바뀌어 현장 업데이트가 거부되는 일을
/// 빌드 단계에서 막는다. 서명·공증 검사는 실제 앱으로 함께 돌린다(`checkSignature`).
public enum OnePercentReleaseCheck {
    public struct Report: Sendable {
        /// Problems. Empty means the ZIP would be accepted. Check failures are localized; setup mistakes are in English.
        public let problems: [String]
        /// The public version read from the app inside the ZIP.
        public let bundleVersion: String?
        public let build: String?
    }

    /// - Parameters:
    ///   - zip: The release asset.
    ///   - tag: The release tag it will be attached to. The asset name, the version and the tag must agree.
    ///   - checkSignature: Also run the Developer ID, `codesign --deep --strict` and notarization checks (needs the real, notarized app).
    ///   - previousVersion: The version of the previous release, if any. With `previousBuild`, the ZIP must be newer than it —
    ///     the same increase check users' Macs run. Without it the increase check is skipped.
    ///   - previousBuild: The `CFBundleVersion` of the previous release.
    public static func check(zip: URL, tag: String, configuration: OnePercentConfiguration, checkSignature: Bool = true,
                             previousVersion: String? = nil, previousBuild: String? = nil) -> Report {
        let table = L10n.current
        var problems = configuration.problems
        if zip.lastPathComponent != configuration.assetFileName(forTag: tag) {
            problems.append("asset name must be \(configuration.assetFileName(forTag: tag)), not \(zip.lastPathComponent)")
        }
        // 앱은 이 크기를 넘는 자산을 안내하지도(selectAsset) 받지도(download) 않는다 — 올리기 전에 같은 상한으로 본다.
        if let size = (try? FileManager.default.attributesOfItem(atPath: zip.path))?[.size] as? Int, size > configuration.limits.maxAssetBytes {
            problems.append("the ZIP is \(size) bytes, over the download limit (limits.maxAssetBytes = \(configuration.limits.maxAssetBytes))")
        }
        guard let version = ReleaseDecision.version(fromTag: tag, configuration: configuration) else {
            return Report(problems: problems + ["tag \(tag) is not a valid version for scheme \(configuration.versionScheme.name)"],
                          bundleVersion: nil, build: nil)
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("OnePercent-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            // 2026-11-20 (리뷰 P1-1): 예전엔 현재 버전을 "0" 으로 넣어, "0" 을 못 읽는 날짜형 규칙에서 정상 ZIP 도 늘 거부됐다.
            // 이전 릴리스를 주면 사용자 Mac 과 같은 상승 검사를 하고, 안 주면 상승 검사를 끈다.
            var input = UpdateVerifier.Input(zip: zip, workDir: work, configuration: configuration,
                                             currentVersion: previousVersion ?? "0", currentBuild: previousBuild, releaseVersion: version)
            input.checkIncrease = previousVersion != nil
            let checks = checkSignature ? BundleChecks.live : BundleChecks(signedByTeam: { _, _ in true }, codesignValid: { _, _ in true },
                                                                         notarizationAccepted: { _ in true })
            let verified = try UpdateVerifier.extractAndVerify(input, checks: checks)
            return Report(problems: problems, bundleVersion: verified.identity.version, build: verified.identity.build)
        } catch let error as OnePercentError {
            // 2026-11-24 (#35): 앱 화면과 같은 코드를 붙인다 — 개발자가 사용자 캡처의 코드와 바로 맞춰 볼 수 있게.
            return Report(problems: problems + ["\(error.message(table)) (\(error.diagnosticCode))"], bundleVersion: nil, build: nil)
        } catch {
            return Report(problems: problems + [error.localizedDescription], bundleVersion: nil, build: nil)
        }
    }
}
