import Foundation

/// Качает один диапазон байт (или весь файл, если range == nil) и пишет его в
/// уже спозиционированный FileHandle. На каждый кусок — свой экземпляр и свой
/// FileHandle, поэтому запись идёт без блокировок (диапазоны не пересекаются).
final class ChunkDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let fileHandle: FileHandle
    private let onBytes: @Sendable (Int64) -> Void
    private let expectedStatus: Set<Int>

    private let lock = NSLock()
    private var cont: CheckedContinuation<Void, Error>?
    private var finished = false
    private var failure: Error?

    init(fileHandle: FileHandle, ranged: Bool, onBytes: @escaping @Sendable (Int64) -> Void) {
        self.fileHandle = fileHandle
        self.onBytes = onBytes
        self.expectedStatus = ranged ? [206] : [200]
    }

    /// `range`: (start, end) включительно, либо nil для одного потока.
    func run(url: URL,
             range: (Int64, Int64)?,
             session ctx: SessionContext,
             urlSession: URLSession) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let range {
            req.setValue("bytes=\(range.0)-\(range.1)", forHTTPHeaderField: "Range")
        }
        ctx.apply(to: &req)

        let task = urlSession.dataTask(with: req)
        task.delegate = self
        // Отмена Swift-таска (cancel/remove в очереди) рвёт сетевой запрос.
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.lock(); cont = c; lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let c = cont
        cont = nil
        lock.unlock()
        switch result {
        case .success: c?.resume(returning: ())
        case .failure(let e): c?.resume(throwing: e)
        }
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        guard let http = response as? HTTPURLResponse else {
            finish(.failure(DownloadError.missingURL))
            return .cancel
        }
        guard expectedStatus.contains(http.statusCode) else {
            finish(.failure(DownloadError.httpStatus(http.statusCode)))
            return .cancel
        }
        return .allow
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        do {
            try fileHandle.write(contentsOf: data)
            onBytes(Int64(data.count))
            RateLimiter.shared.throttle(data.count)   // глобальный лимит скорости (no-op если выкл)
        } catch {
            lock.lock(); failure = DownloadError.writeFailed("\(error)"); lock.unlock()
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        lock.lock(); let pre = failure; lock.unlock()
        if let pre {
            finish(.failure(pre))
        } else if let error {
            finish(.failure(error))
        } else {
            finish(.success(()))
        }
    }
}
