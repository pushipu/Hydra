import Foundation

/// Делегат, который забирает только заголовки ответа и тут же режет соединение,
/// чтобы не качать тело (важно, когда сервер игнорит Range и отдаёт 200 на весь
/// файл).
private final class HeaderOnlyDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<HTTPURLResponse, Error>?
    private var finished = false

    func setContinuation(_ c: CheckedContinuation<HTTPURLResponse, Error>) {
        lock.lock(); defer { lock.unlock() }
        cont = c
    }

    private func finish(_ result: Result<HTTPURLResponse, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let c = cont
        cont = nil
        lock.unlock()
        switch result {
        case .success(let r): c?.resume(returning: r)
        case .failure(let e): c?.resume(throwing: e)
        }
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        if let http = response as? HTTPURLResponse {
            finish(.success(http))
        }
        return .cancel
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            finish(.failure(DownloadError.missingURL))
        }
    }
}

public enum HeaderProbe {
    /// Делает `Range: bytes=0-0` запрос и возвращает метаданные ресурса.
    public static func probe(url: URL,
                             session ctx: SessionContext,
                             urlSession: URLSession) async throws -> RemoteFileInfo {
        guard url.scheme == "http" || url.scheme == "https" else {
            throw DownloadError.unsupportedScheme
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        ctx.apply(to: &req)

        let delegate = HeaderOnlyDelegate()
        let http: HTTPURLResponse = try await withCheckedThrowingContinuation { cont in
            delegate.setContinuation(cont)
            let task = urlSession.dataTask(with: req)
            task.delegate = delegate
            task.resume()
        }

        guard (200...299).contains(http.statusCode) else {
            throw DownloadError.httpStatus(http.statusCode)
        }
        return RemoteFileInfo(http: http, requestedURL: url)
    }
}
