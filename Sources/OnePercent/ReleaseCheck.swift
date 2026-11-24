import Foundation

/// Checks a release ZIP **before** you upload it, with the same code the updater runs on users' Macs — and with the
/// configuration you pass, so pass your app's own (limits, `assetName`, `requireBuildIncrease`). After publishing,
/// ``checkPublished(configuration:checkSignature:previousVersion:previousBuild:)`` checks what apps will really download.
/// 2026-11-22 (#20): 코드는 같아도 설정이 기본값이면 '같은 검사'가 아니었다 — 더 엄격한 상한을 쓰는 앱은 여기서 통과하고
/// 사용자 Mac 에서 거부될 수 있었다. CLI 에 설정 옵션을 더하고, 빠져 있던 ZIP 크기(내려받기 상한) 검사를 넣었다.
/// 2026-11-20: 하늘키보드 `scripts/check_update_zip.swift` 와 같은 생각 — ZIP 만드는 방법이 바뀌어 현장 업데이트가 거부되는 일을
/// 빌드 단계에서 막는다. 서명·공증 검사는 실제 앱으로 함께 돌린다(`checkSignature`).
public enum OnePercentReleaseCheck {
    public struct Report: Sendable {
        /// Problems. Empty means the ZIP would be accepted. Check failures are localized; setup mistakes are in English.
        public let problems: [String]
        /// Not reasons to refuse, but worth fixing before people download the ZIP (in English).
        public let warnings: [String]
        /// The public version read from the app inside the ZIP.
        public let bundleVersion: String?
        public let build: String?
        /// The app's `LSMinimumSystemVersion`, if it has one — Macs below it will not be offered this version (#33).
        public let minimumSystemVersion: String?
        /// The processors the app's executable has code for (`arm64`, `x86_64`). Empty when it could not be read.
        public let architectures: [String]
        /// The release tag that was checked — for ``checkPublished(configuration:checkSignature:previousVersion:previousBuild:)``
        /// the latest release's.
        public let tag: String?

        init(problems: [String], warnings: [String] = [], bundleVersion: String? = nil, build: String? = nil,
             minimumSystemVersion: String? = nil, architectures: [String] = [], tag: String? = nil) {
            self.problems = problems
            self.warnings = warnings
            self.bundleVersion = bundleVersion
            self.build = build
            self.minimumSystemVersion = minimumSystemVersion
            self.architectures = architectures
            self.tag = tag
        }
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
        var warnings = appleDoubleWarning(zip: zip, configuration: configuration).map { [$0] } ?? []
        if zip.lastPathComponent != configuration.assetFileName(forTag: tag) {
            problems.append("asset name must be \(configuration.assetFileName(forTag: tag)), not \(zip.lastPathComponent)")
        }
        // 앱은 이 크기를 넘는 자산을 안내하지도(selectAsset) 받지도(download) 않는다 — 올리기 전에 같은 상한으로 본다.
        if let size = (try? FileManager.default.attributesOfItem(atPath: zip.path))?[.size] as? Int, size > configuration.limits.maxAssetBytes {
            problems.append("the ZIP is \(size) bytes, over the download limit (limits.maxAssetBytes = \(configuration.limits.maxAssetBytes))")
        }
        guard let version = ReleaseDecision.version(fromTag: tag, configuration: configuration) else {
            return Report(problems: problems + ["tag \(tag) is not a valid version for scheme \(configuration.versionScheme.name)"],
                          warnings: warnings, tag: tag)
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
            input.system = nil   // #33: the developer's Mac says nothing about users' Macs
            let checks = checkSignature ? BundleChecks.live : BundleChecks(signedByTeam: { _, _ in true }, codesignValid: { _, _ in true },
                                                                         notarizationAccepted: { _ in true })
            let verified = try UpdateVerifier.extractAndVerify(input, checks: checks)
            // 2026-11-24 (#38): 최소 macOS·프로세서를 알려 준다 — 올린 줄 모르고 올리면, 그보다 낮은 Mac 은 이 버전을 받지 못한다.
            let info = NSDictionary(contentsOf: verified.app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
            let architectures = (SystemProfile.current.architectures(verified.app) ?? []).map(architectureName)
            let minimum = (info?["LSMinimumSystemVersion"] as? String)?.trimmingCharacters(in: .whitespaces)
            // 2026-11-24 (#50, 0.2.0 리뷰): 없으면 어떤 Mac 도 이 버전을 거부하지 않는다 — 손으로 조립한 앱이 빠뜨리기 쉽다.
            if minimum.flatMap(Compatibility.parseVersion) == nil {
                warnings.append("the app has no readable LSMinimumSystemVersion, so apps never refuse this version on an older macOS — "
                                + "if it needs a newer macOS than the release before it, those Macs install an app that does not open")
            }
            return Report(problems: problems, warnings: warnings, bundleVersion: verified.identity.version, build: verified.identity.build,
                          minimumSystemVersion: minimum,
                          architectures: architectures, tag: tag)
        } catch let error as OnePercentError {
            // 2026-11-24 (#35): 앱 화면과 같은 코드를 붙인다 — 개발자가 사용자 캡처의 코드와 바로 맞춰 볼 수 있게.
            return Report(problems: problems + ["\(error.message(table)) (\(error.diagnosticCode))"], warnings: warnings, tag: tag)
        } catch {
            return Report(problems: problems + [error.localizedDescription], warnings: warnings, tag: tag)
        }
    }

    /// Checks the release apps would get **now**: asks GitHub for `configuration.repository`'s latest release exactly the way
    /// apps do (same request, limits, allowed hosts, asset choice, size and SHA-256 checks), downloads its ZIP and runs
    /// ``check(zip:tag:configuration:checkSignature:previousVersion:previousBuild:)`` on it.
    /// GitHub caches answers for up to a minute — right after publishing, wait a minute.
    public static func checkPublished(configuration: OnePercentConfiguration, checkSignature: Bool = true,
                                      previousVersion: String? = nil, previousBuild: String? = nil) async -> Report {
        await checkPublished(configuration: configuration, checkSignature: checkSignature, previousVersion: previousVersion,
                             previousBuild: previousBuild, session: OnePercentUpdater.sessionConfiguration())
    }

    static func checkPublished(configuration: OnePercentConfiguration, checkSignature: Bool, previousVersion: String?,
                               previousBuild: String?, session: URLSessionConfiguration) async -> Report {
        let problems = configuration.problems
        guard problems.isEmpty else { return Report(problems: problems) }
        let userAgent = "onepercent-check"
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("OnePercent-published-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        var tag: String?
        do {
            let release = try await GitHubReleases.latest(repository: configuration.repository, configuration: configuration,
                                                          session: session, userAgent: userAgent)
            tag = release.tag
            guard ReleaseDecision.version(fromTag: release.tag, configuration: configuration) != nil else {
                return Report(problems: ["the latest release's tag \(release.tag) is not a \(configuration.versionScheme.name) version "
                                         + "with tag prefix \"\(configuration.tagPrefix)\" — apps report a settings error"], tag: tag)
            }
            guard let asset = ReleaseDecision.selectAsset(in: release, configuration: configuration) else {
                return Report(problems: [missingAssetReason(release, configuration: configuration)], tag: tag)
            }
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent(configuration.assetFileName(forTag: release.tag))
            try await GitHubReleases.download(asset, to: zip, configuration: configuration, session: session, userAgent: userAgent)
            return check(zip: zip, tag: release.tag, configuration: configuration, checkSignature: checkSignature,
                         previousVersion: previousVersion, previousBuild: previousBuild)
        } catch let error as OnePercentError {
            return Report(problems: ["\(error.message(L10n.current)) (\(error.diagnosticCode))"], tag: tag)
        } catch {
            return Report(problems: ["\(error.localizedDescription) (network)"], tag: tag)
        }
    }

    /// Why apps find no installable ZIP on `release`. Apps then say "the installer for version … isn't ready yet".
    static func missingAssetReason(_ release: ReleaseInfo, configuration: OnePercentConfiguration) -> String {
        let wanted = configuration.assetFileName(forTag: release.tag)
        let prefix = "the latest release \(release.tag) has no ZIP apps can use (apps report assetNotReady): "
        guard let named = release.assets.first(where: { $0.name == wanted }) else {
            let names = release.assets.map(\.name)
            return prefix + "no asset named \(wanted)" + (names.isEmpty ? " — it has no assets" : " — it has \(names.joined(separator: ", "))")
        }
        if named.size > configuration.limits.maxAssetBytes {
            return prefix + "\(wanted) is \(named.size) bytes, over the download limit (limits.maxAssetBytes = \(configuration.limits.maxAssetBytes))"
        }
        return prefix + "\(wanted) is not served from github.com/\(configuration.repository)/releases/download/"
    }

    /// A warning when the ZIP holds AppleDouble entries (`._name`, `__MACOSX/`).
    /// 2026-11-24 (#38) 실측: `--norsrc` 없이 만든 시험 앱 ZIP 에 `._` 항목 70개(확장 속성 `com.apple.provenance` 몫).
    /// `ditto -x -k`(OnePercent)는 확장 속성으로 되돌려 서명이 멀쩡하지만, `unzip` 으로 풀면 앱 안에 파일로 남아
    /// "a sealed resource is missing or invalid" — 릴리스 페이지에서 직접 받는 사람이 겪는다.
    static func appleDoubleWarning(zip: URL, configuration: OnePercentConfiguration) -> String? {
        guard let entries = try? UpdateVerifier.listing(zip) else { return nil }
        let count = entries.filter { entry in
            let parts = entry.name.split(separator: "/")
            return parts.first == "__MACOSX" || parts.contains { $0.hasPrefix("._") }
        }.count
        guard count > 0 else { return nil }
        return "the ZIP has \(count) AppleDouble entries (._*), so it was made without ditto's --norsrc. OnePercent unpacks it "
            + "correctly, but people who download it and unzip it with other tools get those files inside the app, which breaks its "
            + "signature. Make it with: ditto -c -k --norsrc --keepParent \(configuration.appFolderName) \(zip.lastPathComponent)"
    }

    static func architectureName(_ type: Int) -> String {
        switch type {
        case NSBundleExecutableArchitectureARM64: "arm64"
        case NSBundleExecutableArchitectureX86_64: "x86_64"
        default: String(format: "cpu type 0x%08x", type)
        }
    }
}
