import CryptoKit
import Foundation
import Darwin

/// What a transfer returned. `data` is empty when the body went to a file; `sha256` is set only then.
struct Received: Sendable {
    let data: Data
    let response: HTTPURLResponse
    let sha256: String?
}

/// Receives JSON or a ZIP with a size limit enforced **while** receiving. A ZIP goes straight to disk, never into memory.
/// State is touched only on one serial queue shared by the URLSession delegate and start/cancel.
///
/// 2026-11-20: 하늘키보드 `UpdateTransport`(#66) 를 옮기며 허용 호스트를 설정값으로 받고, 진행률 보고를 더했다(Fable 리뷰 — 진행률·취소 없음).
final class UpdateTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Progress = @Sendable (_ received: Int64, _ expected: Int64?) -> Void

    private let queue = DispatchQueue(label: "OnePercent.transfer")
    private let limit: Int
    private let destination: URL?
    private let allowedHosts: Set<String>
    private let progress: Progress?
    private var continuation: CheckedContinuation<Received, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var received = 0
    private var expected: Int64?
    private var file: FileHandle?
    private var hasher: SHA256?
    private var ownsFile = false
    private var cancelled = false

    private init(limit: Int, destination: URL?, allowedHosts: Set<String>, progress: Progress?) {
        self.limit = limit
        self.destination = destination
        self.allowedHosts = allowedHosts
        self.progress = progress
    }

    static func receive(_ request: URLRequest, configuration: URLSessionConfiguration, limit: Int,
                        allowedHosts: Set<String>, destination: URL? = nil,
                        progress: Progress? = nil) async throws -> Received {
        let transfer = UpdateTransport(limit: limit, destination: destination, allowedHosts: allowedHosts, progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transfer.queue.async {
                    transfer.start(request, configuration: configuration, continuation: continuation)
                }
            }
        } onCancel: {
            transfer.queue.async {
                transfer.cancelled = true
                transfer.finish(.failure(CancellationError()))
            }
        }
    }

    private func start(_ request: URLRequest, configuration: URLSessionConfiguration,
                       continuation: CheckedContinuation<Received, Error>) {
        self.continuation = continuation
        if cancelled { finish(.failure(CancellationError())); return }
        guard limit > 0, let url = request.url, ReleaseDecision.isAllowedURL(url, hosts: allowedHosts) else {
            finish(.failure(OnePercentError.redirectBlocked(ReleaseDecision.display(request.url?.absoluteString))))
            return
        }
        if let destination {
            // 이미 있는 파일이나 심볼릭 링크를 덮어쓰지 않는다. 사용자 전용(0600).
            let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else {
                finish(.failure(NSError(domain: NSPOSIXErrorDomain, code: Int(errno))))
                return
            }
            ownsFile = true
            file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            hasher = SHA256()
        }
        let delegates = OperationQueue()
        delegates.maxConcurrentOperationCount = 1
        delegates.underlyingQueue = queue
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegates)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard continuation != nil else { completionHandler(.cancel); return }
        guard let http = response as? HTTPURLResponse, let url = http.url,
              ReleaseDecision.isAllowedURL(url, hosts: allowedHosts) else {
            completionHandler(.cancel)
            finish(.failure(OnePercentError.malformedResponse))
            return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel)
            finish(.failure(OnePercentError.responseTooLarge(limit)))
            return
        }
        self.response = http
        expected = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard continuation != nil else { return }
        // Content-Length 가 없거나 거짓이어도 실제로 받은 바이트로 따로 제한한다.
        guard chunk.count <= limit - received else {
            finish(.failure(OnePercentError.responseTooLarge(limit)))
            return
        }
        do {
            if let file {
                try file.write(contentsOf: chunk)
                hasher?.update(data: chunk)
            } else {
                data.append(chunk)
            }
            received += chunk.count
            progress?(Int64(received), expected)
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard continuation != nil, let url = request.url, ReleaseDecision.isAllowedURL(url, hosts: allowedHosts) else {
            completionHandler(nil)
            finish(.failure(OnePercentError.redirectBlocked(ReleaseDecision.display(request.url?.absoluteString))))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        else if let response {
            let digest = hasher.map { $0.finalize().map { String(format: "%02x", $0) }.joined() }
            finish(.success(Received(data: data, response: response, sha256: digest)))
        }
        else { finish(.failure(OnePercentError.malformedResponse)) }
    }

    private func finish(_ result: Result<Received, Error>) {
        guard let continuation else { return }   // 취소·완료가 겹쳐도 한 번만 재개한다.
        self.continuation = nil
        var result = result
        do { try file?.close() } catch { result = .failure(error) }
        file = nil
        hasher = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        if case .failure = result, ownsFile, let destination {
            try? FileManager.default.removeItem(at: destination)
        }
        data = Data()
        continuation.resume(with: result)
    }
}
