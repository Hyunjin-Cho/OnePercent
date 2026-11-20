import Foundation
@testable import OnePercent

/// A fake network for one suite at a time (suites that use it are `.serialized` and share one global lock-protected state).
/// Responses are chosen by URL path. Nothing leaves the machine.
final class NetworkStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int = 200
        var body: Data = Data()
        var chunkSize: Int? = nil
        var contentLength: Int? = nil
        var redirect: URL? = nil
        var failAfterChunks: Int? = nil
        /// Send this many chunks, then wait until `release()`.
        var holdAfterChunks: Int? = nil
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    nonisolated(unsafe) private static var held: [() -> Void] = []
    nonisolated(unsafe) private static var holding = 0
    nonisolated(unsafe) private static var headers: [String: [String: String]] = [:]

    static func reset() { lock.withLock { replies = [:]; counts = [:]; held = []; holding = 0; headers = [:] } }
    static func set(_ path: String, _ reply: Reply) { lock.withLock { replies[path] = reply } }
    static func count(_ path: String) -> Int { lock.withLock { counts[path] ?? 0 } }
    static func lastHeaders(_ path: String) -> [String: String]? { lock.withLock { headers[path] } }
    static var isHolding: Bool { lock.withLock { holding > 0 } }
    static func release() {
        let pending = lock.withLock { () -> [() -> Void] in let list = held; held = []; holding = 0; return list }
        pending.forEach { $0() }
    }

    static func session() -> URLSession {
        let config = OnePercentUpdater.sessionConfiguration()
        config.protocolClasses = [NetworkStub.self]
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }

    private let state = NSLock()
    nonisolated(unsafe) private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let path = url.path
        let reply = Self.lock.withLock { () -> Reply? in
            Self.counts[path, default: 0] += 1
            Self.headers[path] = request.allHTTPHeaderFields ?? [:]
            return Self.replies[path]
        }
        guard let reply else {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if let target = reply.redirect {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            return
        }
        let length = reply.contentLength ?? reply.body.count
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": String(length)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let size = max(1, reply.chunkSize ?? max(reply.body.count, 1))
        let chunks = stride(from: 0, to: reply.body.count, by: size).map { reply.body.subdata(in: $0..<min($0 + size, reply.body.count)) }
        send(chunks, index: 0, reply: reply)
    }

    private func send(_ chunks: [Data], index: Int, reply: Reply) {
        if state.withLock({ stopped }) { return }
        if let hold = reply.holdAfterChunks, index == hold {
            Self.lock.withLock {
                Self.holding += 1
                Self.held.append { [self] in
                    var resumed = reply
                    resumed.holdAfterChunks = nil
                    send(chunks, index: index, reply: resumed)
                }
            }
            return
        }
        if let fail = reply.failAfterChunks, index == fail {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        guard index < chunks.count else { client?.urlProtocolDidFinishLoading(self); return }
        client?.urlProtocol(self, didLoad: chunks[index])
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(2)) { [self] in send(chunks, index: index + 1, reply: reply) }
    }

    override func stopLoading() { state.withLock { stopped = true } }
}

enum ReleaseJSON {
    static let apiPath = "/repos/owner/TestApp/releases/latest"
    static func assetPath(_ tag: String) -> String { "/owner/TestApp/releases/download/\(tag)/TestApp_\(tag).zip" }

    static func body(tag: String, asset: Bool = true, size: Int = 100, digest: String? = nil) -> Data {
        var item: [String: Any] = ["name": "TestApp_\(tag).zip", "size": size,
                                   "browser_download_url": "https://github.com\(assetPath(tag))"]
        if let digest { item["digest"] = "sha256:" + digest }
        let object: [String: Any] = ["tag_name": tag, "draft": false, "prerelease": false,
                                     "html_url": "https://github.com/owner/TestApp/releases/tag/\(tag)",
                                     "assets": asset ? [item] : []]
        return try! JSONSerialization.data(withJSONObject: object)
    }
}
