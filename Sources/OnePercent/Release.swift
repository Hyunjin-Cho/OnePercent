import Foundation

/// One file attached to a GitHub release.
public struct ReleaseAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    /// The API's `size` in bytes, or 0 when unknown.
    public let size: Int
    /// The API's `digest` as 64 lowercase hex characters, when GitHub provides a SHA-256 for the file.
    public let sha256: String?

    public init(name: String, downloadURL: URL, size: Int, sha256: String? = nil) {
        self.name = name
        self.downloadURL = downloadURL
        self.size = size
        self.sha256 = sha256
    }
}

/// The parts of a GitHub release OnePercent uses.
public struct ReleaseInfo: Equatable, Sendable {
    /// `tag_name`.
    public let tag: String
    public let assets: [ReleaseAsset]
    /// `html_url` — only when it is HTTPS on an allowed host (it is opened in the browser as "release notes").
    public let pageURL: URL?
    /// `body` — the release notes as written on GitHub (Markdown). Shown as text only.
    public let notes: String?
}

/// A newer release with a downloadable, well-formed asset.
public struct AvailableUpdate: Equatable, Sendable {
    /// The release tag, for example `v1.2.0`.
    public let tag: String
    /// The tag without ``OnePercentConfiguration/tagPrefix`` — the version as the app shows it.
    public let version: String
    public let asset: ReleaseAsset
    public let pageURL: URL?
    public let notes: String?
}

/// Pure decisions about releases. No network, no files.
enum ReleaseDecision {
    /// `GET https://api.github.com/repos/<owner>/<name>/releases/latest` — this endpoint never returns drafts or pre-releases.
    static func latestReleaseURL(repository: String) -> URL? {
        guard OnePercentConfiguration.isValidRepository(repository) else { return nil }
        return URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
    }

    /// HTTPS and an allowed host.
    static func isAllowedURL(_ url: URL, hosts: Set<String>) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return hosts.contains(host)
    }

    /// Only the fields OnePercent needs. `nil` when `tag_name` is missing, or when the response says draft/pre-release
    /// (the endpoint filters those; a response that still has them is not trusted).
    static func parseRelease(_ data: Data, allowedHosts: Set<String>) -> ReleaseInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let tag = dict["tag_name"] as? String, !tag.isEmpty else { return nil }
        if dict["draft"] as? Bool == true || dict["prerelease"] as? Bool == true { return nil }
        var assets: [ReleaseAsset] = []
        for item in (dict["assets"] as? [[String: Any]]) ?? [] {
            guard let name = item["name"] as? String,
                  let urlString = item["browser_download_url"] as? String,
                  let url = URL(string: urlString) else { continue }
            let size = item["size"] as? Int ?? 0
            assets.append(ReleaseAsset(name: name, downloadURL: url, size: max(0, size), sha256: sha256(fromDigest: item["digest"])))
        }
        // 2026-09-21 (하늘키보드 #19 P2-1): 릴리스 페이지 주소도 다운로드 주소와 같은 문지기를 통과한 것만 쓴다 —
        // 브라우저로 그대로 열리므로, 응답이 바뀌치기되면 임의 주소를 여는 통로가 된다. 통과 못 하면 링크만 안 보인다.
        let pageURL = (dict["html_url"] as? String)
            .flatMap(URL.init(string:))
            .flatMap { isAllowedURL($0, hosts: allowedHosts) ? $0 : nil }
        let notes = (dict["body"] as? String).map { String($0.prefix(20_000)) }
        return ReleaseInfo(tag: tag, assets: assets, pageURL: pageURL, notes: notes)
    }

    /// GitHub's asset `digest` (`sha256:` + 64 hex). Anything else — missing, `null`, another algorithm, malformed — is `nil`.
    /// 2026-11-20 (리서치 P9): GitHub 가 자산마다 계산해 주는 값. 받으면서 해시해 대조한다. 진위는 여전히 코드 서명이 맡는다.
    static func sha256(fromDigest value: Any?) -> String? {
        guard let text = value as? String, text.hasPrefix("sha256:") else { return nil }
        let hex = text.dropFirst("sha256:".count).lowercased()
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        return hex
    }

    /// The tag without the configured prefix, if the tag starts with it and the rest is a valid version.
    static func version(fromTag tag: String, configuration: OnePercentConfiguration) -> String? {
        guard tag.hasPrefix(configuration.tagPrefix) else { return nil }
        let version = String(tag.dropFirst(configuration.tagPrefix.count))
        return configuration.versionScheme.isValid(version) ? version : nil
    }

    /// The asset whose name is exactly the configured asset name, on an allowed HTTPS host, within the size limit.
    static func selectAsset(in release: ReleaseInfo, configuration: OnePercentConfiguration) -> ReleaseAsset? {
        let wanted = configuration.assetFileName(forTag: release.tag)
        guard !wanted.isEmpty, !wanted.contains("/"), !wanted.hasPrefix(".") else { return nil }
        return release.assets.first {
            $0.name == wanted && isAllowedURL($0.downloadURL, hosts: configuration.allowedHosts)
                && $0.size <= configuration.limits.maxAssetBytes
        }
    }

    /// "Update available" — only when the release is newer than `currentVersion` **and** has a usable asset.
    static func availableUpdate(currentVersion: String, release: ReleaseInfo,
                                configuration: OnePercentConfiguration) -> AvailableUpdate? {
        guard let version = version(fromTag: release.tag, configuration: configuration),
              configuration.versionScheme.isNewer(version, than: currentVersion),
              let asset = selectAsset(in: release, configuration: configuration) else { return nil }
        return AvailableUpdate(tag: release.tag, version: version, asset: asset, pageURL: release.pageURL, notes: release.notes)
    }

    /// The release page for a tag, built without a server response (after relaunch).
    /// The tag must be made of plain characters and its version part must be valid.
    static func releasePageURL(tag: String, configuration: OnePercentConfiguration) -> URL? {
        guard OnePercentConfiguration.isValidRepository(configuration.repository),
              !tag.isEmpty, tag.allSatisfy(OnePercentConfiguration.isTagCharacter),
              version(fromTag: tag, configuration: configuration) != nil else { return nil }
        return URL(string: "https://github.com/\(configuration.repository)/releases/tag/\(tag)")
    }
}
