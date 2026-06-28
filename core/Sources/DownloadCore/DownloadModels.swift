import Foundation

/// Запрос на загрузку, как его формирует расширение/хост.
public struct DownloadRequest: Sendable {
    public var url: URL
    public var session: SessionContext
    public var suggestedFilename: String?
    public var destinationDirectory: URL
    /// Максимум параллельных соединений (потоков) на один файл.
    public var maxConnections: Int
    /// Минимальный размер куска — не дробим мелкие файлы.
    public var minChunkSize: Int64

    public init(url: URL,
                session: SessionContext = SessionContext(),
                suggestedFilename: String? = nil,
                destinationDirectory: URL,
                maxConnections: Int = 8,
                minChunkSize: Int64 = 1 * 1024 * 1024) {
        self.url = url
        self.session = session
        self.suggestedFilename = suggestedFilename
        self.destinationDirectory = destinationDirectory
        self.maxConnections = max(1, maxConnections)
        self.minChunkSize = max(64 * 1024, minChunkSize)
    }
}

/// Состояние одного блока файла (для «дефраг»-сетки).
public enum BlockState: UInt8, Sendable { case empty = 0, active = 1, done = 2 }

/// Что прямо сейчас тянет одно соединение (для списка сегментов).
public struct SegmentInfo: Sendable, Identifiable {
    public let id: Int          // индекс воркера
    public var range: ClosedRange<Int64>
    public var received: Int64
    public init(id: Int, range: ClosedRange<Int64>, received: Int64) {
        self.id = id; self.range = range; self.received = received
    }
}

/// Снимок прогресса загрузки.
public struct DownloadProgress: Sendable {
    public var totalBytes: Int64?
    public var receivedBytes: Int64
    public var connections: Int
    public var bytesPerSecond: Double
    /// Карта блоков для дефраг-сетки (nil для одно-поточной/неизвестного размера).
    public var blocks: [BlockState]?
    /// Активные сегменты по соединениям.
    public var segments: [SegmentInfo]?

    public init(totalBytes: Int64?, receivedBytes: Int64, connections: Int, bytesPerSecond: Double,
                blocks: [BlockState]? = nil, segments: [SegmentInfo]? = nil) {
        self.totalBytes = totalBytes
        self.receivedBytes = receivedBytes
        self.connections = connections
        self.bytesPerSecond = bytesPerSecond
        self.blocks = blocks
        self.segments = segments
    }

    public var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1.0, Double(receivedBytes) / Double(totalBytes))
    }
}

public enum DownloadError: Error, Equatable {
    case unsupportedScheme
    case httpStatus(Int)
    case missingURL
    case rangeNotSatisfiable
    case writeFailed(String)
    case insufficientSpace(needBytes: Int64)
    case destinationUnwritable
}

/// Метаданные ресурса, полученные из probe-запроса.
public struct RemoteFileInfo: Sendable {
    public var url: URL
    public var contentLength: Int64?
    public var acceptsRanges: Bool
    public var etag: String?
    public var suggestedFilename: String?

    init(http: HTTPURLResponse, requestedURL: URL) {
        self.url = http.url ?? requestedURL
        self.acceptsRanges = false
        self.contentLength = nil

        let status = http.statusCode

        // Range считаем поддержанным ТОЛЬКО если probe реально вернул 206.
        // Заголовку Accept-Ranges на 200-ответе не доверяем: некоторые CDN
        // (Cloudflare и пр.) шлют «Accept-Ranges: bytes», но фактический ranged-GET
        // отдают 200 целиком — тогда многопоточная сборка ломается. Лучше честно
        // уйти в один поток, чем словить httpStatus(200) на воркере.
        if status == 206 {
            self.acceptsRanges = true
            // Content-Range: bytes 0-0/12345
            if let cr = http.value(forHTTPHeaderField: "Content-Range"),
               let slash = cr.lastIndex(of: "/") {
                let totalStr = cr[cr.index(after: slash)...].trimmingCharacters(in: .whitespaces)
                if totalStr != "*", let total = Int64(totalStr) {
                    self.contentLength = total
                }
            }
        } else if status == 200 {
            // expectedContentLength == Content-Length всего файла.
            if http.expectedContentLength > 0 {
                self.contentLength = http.expectedContentLength
            }
        }

        self.etag = http.value(forHTTPHeaderField: "ETag")
        self.suggestedFilename = Self.filename(fromContentDisposition:
            http.value(forHTTPHeaderField: "Content-Disposition"))
    }

    static func filename(fromContentDisposition value: String?) -> String? {
        guard let value else { return nil }
        // filename*=UTF-8''name.ext  (приоритетнее)
        if let r = value.range(of: "filename*=") {
            var s = String(value[r.upperBound...])
            if let semi = s.firstIndex(of: ";") { s = String(s[..<semi]) }
            if let tick = s.range(of: "''") { s = String(s[tick.upperBound...]) }
            if let decoded = s.removingPercentEncoding, !decoded.isEmpty {
                return decoded.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
        }
        if let r = value.range(of: "filename=") {
            var s = String(value[r.upperBound...])
            if let semi = s.firstIndex(of: ";") { s = String(s[..<semi]) }
            return s.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return nil
    }
}
