import Foundation

/// The two requests OnePercent makes to GitHub — the latest release, and its ZIP. The updater and
/// ``OnePercentReleaseCheck/checkPublished(configuration:checkSignature:previousVersion:previousBuild:)`` share them,
/// so the check after publishing sees exactly what apps see.
///
/// 2026-11-24 (#38): `OnePercentUpdater` 안의 두 함수를 옮겼다(동작은 그대로). 올린 뒤 검사가 따로 짠 코드를 쓰면 "앱과 같은 검사"가 아니다.
enum GitHubReleases {
    /// The headers OnePercent sets: `Accept`, `User-Agent`, and a fixed `Accept-Language: en`
    /// (setting it stops URLSession from sending the user's language list — 2026-11-13 하늘키보드 실측).
    static func request(for url: URL, userAgent: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// The repository's latest release (drafts and pre-releases never count).
    static func latest(repository: String, configuration: OnePercentConfiguration, session: URLSessionConfiguration,
                       userAgent: String) async throws -> ReleaseInfo {
        guard let url = ReleaseDecision.latestReleaseURL(repository: repository) else { throw OnePercentError.badConfiguration("repository") }
        let received = try await UpdateTransport.receive(request(for: url, userAgent: userAgent), configuration: session,
                                                         limit: configuration.limits.maxMetadataBytes,
                                                         allowedHosts: configuration.allowedHosts)
        let http = received.response
        switch http.statusCode {
        case 200:
            guard let release = ReleaseDecision.parseRelease(received.data, allowedHosts: configuration.allowedHosts) else {
                throw OnePercentError.malformedResponse
            }
            return release
        case 300...399: throw OnePercentError.redirectBlocked(ReleaseDecision.display(http.value(forHTTPHeaderField: "Location")))
        case 404: throw OnePercentError.noRelease(repository)
        case 403, 429: throw OnePercentError.rateLimited
        default: throw OnePercentError.httpStatus(http.statusCode)
        }
    }

    /// Downloads `asset` to `destination` within the size limit and the allowed hosts, then checks the size GitHub
    /// published and — when GitHub gives one — the SHA-256.
    static func download(_ asset: ReleaseAsset, to destination: URL, configuration: OnePercentConfiguration,
                         session: URLSessionConfiguration, userAgent: String,
                         progress: UpdateTransport.Progress? = nil) async throws {
        let received = try await UpdateTransport.receive(request(for: asset.downloadURL, userAgent: userAgent), configuration: session,
                                                         limit: configuration.limits.maxAssetBytes,
                                                         allowedHosts: configuration.allowedHosts,
                                                         destination: destination, progress: progress)
        let http = received.response
        guard http.statusCode == 200 else {
            if (300...399).contains(http.statusCode) {
                throw OnePercentError.redirectBlocked(ReleaseDecision.display(http.value(forHTTPHeaderField: "Location")))
            }
            throw OnePercentError.httpStatus(http.statusCode)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? Int ?? 0
        guard size > 0, size <= configuration.limits.maxAssetBytes else { throw OnePercentError.badSize(size) }
        if asset.size > 0, asset.size != size { throw OnePercentError.sizeMismatch(expected: asset.size, actual: size) }
        // 2026-11-20 (리서치 P9): GitHub 가 지문을 주면 받으면서 잰 값과 대조한다. 안 주면(옛 릴리스) 크기와 코드 서명으로만 본다.
        if let expected = asset.sha256, received.sha256 != expected { throw OnePercentError.digestMismatch }
    }
}
