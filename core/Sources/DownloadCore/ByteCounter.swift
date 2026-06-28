import Foundation

/// Потокобезопасный агрегатор принятых байт по всем кускам + троттлинг прогресса.
final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var received: Int64 = 0
    private var lastEmit: Date = .distantPast
    private let startedAt: Date
    private let total: Int64?
    private let connections: Int
    private let onProgress: (@Sendable (DownloadProgress) -> Void)?

    init(total: Int64?, connections: Int, startedAt: Date,
         onProgress: (@Sendable (DownloadProgress) -> Void)?) {
        self.total = total
        self.connections = connections
        self.startedAt = startedAt
        self.onProgress = onProgress
    }

    func add(_ delta: Int64, now: Date = Date()) {
        guard let onProgress else {
            lock.lock(); received += delta; lock.unlock()
            return
        }
        lock.lock()
        received += delta
        let r = received
        let shouldEmit = now.timeIntervalSince(lastEmit) >= 0.1
        if shouldEmit { lastEmit = now }
        lock.unlock()

        guard shouldEmit else { return }
        let elapsed = max(0.001, now.timeIntervalSince(startedAt))
        onProgress(DownloadProgress(totalBytes: total,
                                    receivedBytes: r,
                                    connections: connections,
                                    bytesPerSecond: Double(r) / elapsed))
    }
}
