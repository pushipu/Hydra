import Foundation

/// Запись истории — завершённая загрузка. Переживает перезапуск.
public struct HistoryEntry: Codable, Sendable, Identifiable {
    public var id: String
    public var url: URL
    public var filename: String
    public var path: String
    public var size: Int64
    public var completedAt: Date
    public var origin: String?       // источник добавления (токен TaskSource); nil у старых записей

    public init(id: String = UUID().uuidString, url: URL, filename: String,
                path: String, size: Int64, completedAt: Date, origin: String? = nil) {
        self.id = id; self.url = url; self.filename = filename
        self.path = path; self.size = size; self.completedAt = completedAt; self.origin = origin
    }
}

/// История скачиваний в ~/Library/Application Support/Hydra/history.json (последние 500).
public final class HistoryStore: @unchecked Sendable {
    public static let shared = HistoryStore()
    private let lock = NSLock()
    private let cap = 500

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Hydra", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    public func load() -> [HistoryEntry] {
        lock.lock(); defer { lock.unlock() }
        return (try? JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: fileURL))) ?? []
    }

    private func save(_ list: [HistoryEntry]) {
        if let data = try? JSONEncoder().encode(Array(list.prefix(cap))) { try? data.write(to: fileURL) }
    }

    public func append(_ entry: HistoryEntry) {
        lock.lock(); defer { lock.unlock() }
        var list = (try? JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: fileURL))) ?? []
        list.insert(entry, at: 0)   // новые сверху
        save(list)
    }

    public func remove(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        var list = (try? JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: fileURL))) ?? []
        list.removeAll { $0.id == id }
        save(list)
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
