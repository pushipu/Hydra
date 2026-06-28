import Foundation

/// Точка входа в ядро: probe → план → параллельная загрузка → сборка.
public struct Downloader {
    public let urlSession: URLSession

    public init(configuration: URLSessionConfiguration? = nil) {
        let cfg = configuration ?? .ephemeral
        // Куки/сессией управляем вручную через SessionContext — пусть URLSession
        // не подмешивает своё хранилище кук.
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpMaximumConnectionsPerHost = 16
        // Concurrent delegate-очередь: throttle (RateLimiter) спит в didReceive,
        // и сон одного потока не должен стопорить остальные.
        let dq = OperationQueue(); dq.maxConcurrentOperationCount = 16
        self.urlSession = URLSession(configuration: cfg, delegate: nil, delegateQueue: dq)
    }

    public func download(_ request: DownloadRequest,
                         progress: (@Sendable (DownloadProgress) -> Void)? = nil) async throws -> URL {
        let info = try await HeaderProbe.probe(url: request.url,
                                               session: request.session,
                                               urlSession: urlSession)

        let fm = FileManager.default
        try fm.createDirectory(at: request.destinationDirectory,
                               withIntermediateDirectories: true)

        let filename = Self.resolveFilename(request: request, info: info)
        let finalURL = Self.uniqueDestination(directory: request.destinationDirectory,
                                              filename: filename)
        let partURL = finalURL.appendingPathExtension("hydrapart")

        let canMultipart = info.acceptsRanges
            && request.maxConnections > 1
            && (info.contentLength ?? 0) >= request.minChunkSize * 2

        let startedAt = Date()

        if canMultipart, let total = info.contentLength {
            let chunks = Self.planChunks(total: total,
                                         maxConnections: request.maxConnections,
                                         minChunkSize: request.minChunkSize)
            try Self.preallocate(at: partURL, size: total)
            let counter = ByteCounter(total: total, connections: chunks.count,
                                      startedAt: startedAt, onProgress: progress)
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for chunk in chunks {
                        group.addTask {
                            let fh = try FileHandle(forWritingTo: partURL)
                            defer { try? fh.close() }
                            try fh.seek(toOffset: UInt64(chunk.0))
                            let cd = ChunkDownloader(fileHandle: fh, ranged: true, onBytes: { counter.add($0) })
                            try await cd.run(url: info.url, range: chunk,
                                             session: request.session,
                                             urlSession: urlSession)
                        }
                    }
                    try await group.waitForAll()
                }
            } catch {
                try? fm.removeItem(at: partURL)
                throw error
            }
        } else {
            // Один поток: размер может быть неизвестен.
            let counter = ByteCounter(total: info.contentLength, connections: 1,
                                      startedAt: startedAt, onProgress: progress)
            fm.createFile(atPath: partURL.path, contents: nil)
            do {
                let fh = try FileHandle(forWritingTo: partURL)
                defer { try? fh.close() }
                let cd = ChunkDownloader(fileHandle: fh, ranged: false, onBytes: { counter.add($0) })
                try await cd.run(url: info.url, range: nil,
                                 session: request.session, urlSession: urlSession)
            } catch {
                try? fm.removeItem(at: partURL)
                throw error
            }
        }

        // Атомарно переносим .hydrapart → финал.
        if fm.fileExists(atPath: finalURL.path) {
            try? fm.removeItem(at: finalURL)
        }
        try fm.moveItem(at: partURL, to: finalURL)
        return finalURL
    }

    // MARK: - Планирование

    /// Возвращает список (start, end) включительных диапазонов.
    static func planChunks(total: Int64, maxConnections: Int, minChunkSize: Int64) -> [(Int64, Int64)] {
        let byMin = max(1, Int(total / max(1, minChunkSize)))
        let n = max(1, min(maxConnections, byMin))
        let base = total / Int64(n)
        let remainder = total % Int64(n)
        var chunks: [(Int64, Int64)] = []
        var start: Int64 = 0
        for i in 0..<n {
            let len = base + (Int64(i) < remainder ? 1 : 0)
            let end = start + len - 1
            chunks.append((start, end))
            start = end + 1
        }
        return chunks
    }

    static func preallocate(at url: URL, size: Int64) throws {
        let fm = FileManager.default
        fm.createFile(atPath: url.path, contents: nil)
        let fh = try FileHandle(forWritingTo: url)
        defer { try? fh.close() }
        try fh.truncate(atOffset: UInt64(size))
    }

    // MARK: - Имена файлов

    static func resolveFilename(request: DownloadRequest, info: RemoteFileInfo) -> String {
        let bad = CharacterSet(charactersIn: "/\\:\0")
        func clean(_ name: String) -> String {
            let c = name.components(separatedBy: bad).joined(separator: "_")
            return c.isEmpty ? "download" : c
        }
        if let f = request.suggestedFilename, !f.isEmpty { return clean(f) }
        if let f = info.suggestedFilename, !f.isEmpty { return clean(f) }
        let last = info.url.lastPathComponent
        if !last.isEmpty, last != "/" {
            return clean(last.removingPercentEncoding ?? last)
        }
        return "download"
    }

    static func uniqueDestination(directory: URL, filename: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(filename)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let ext = (filename as NSString).pathExtension
        let stem = (filename as NSString).deletingPathExtension
        var i = 1
        while fm.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(stem) (\(i))" : "\(stem) (\(i)).\(ext)"
            candidate = directory.appendingPathComponent(next)
            i += 1
        }
        return candidate
    }
}
