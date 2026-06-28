import Foundation

/// Персистентное состояние блочной загрузки: всё, чтобы докачать после
/// перезапуска приложения. Хранится в ~/Library/Application Support/Hydra/downloads/<id>.json.
public struct DownloadMeta: Codable, Sendable {
    public var id: String
    public var url: URL
    public var filename: String
    public var destinationDir: URL
    public var partPath: String          // абсолютный путь к .hydrapart
    public var total: Int64
    public var blockSize: Int64
    public var doneBlocks: [Bool]        // битовая карта готовых блоков
    public var etag: String?
    public var headers: [String: String] // сессия (Cookie/User-Agent/Referer/…)
    public var connections: Int
    public var wasRunning: Bool          // качалось на момент выхода → авто-резюм при старте
    public var createdAt: Date

    public func blockRange(_ i: Int) -> (Int64, Int64) {
        let start = Int64(i) * blockSize
        let end = min(start + blockSize, total) - 1
        return (start, end)
    }

    public var completedBytes: Int64 {
        var sum: Int64 = 0
        for i in 0..<doneBlocks.count where doneBlocks[i] {
            let (s, e) = blockRange(i); sum += e - s + 1
        }
        return sum
    }
}

/// Хранилище метаданных загрузок на диске.
public final class DownloadStore: @unchecked Sendable {
    public static let shared = DownloadStore()
    private let dir: URL
    private let lock = NSLock()

    public init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Hydra/downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Для тестов: своя директория, чтобы не трогать общий app-support.
    public init(directory: URL) {
        dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func file(_ id: String) -> URL { dir.appendingPathComponent("\(id).json") }

    public func save(_ meta: DownloadMeta) {
        lock.lock(); defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(meta) { try? data.write(to: file(meta.id)) }
    }

    public func delete(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: file(id))
    }

    public func loadAll() -> [DownloadMeta] {
        lock.lock(); defer { lock.unlock() }
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(DownloadMeta.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
