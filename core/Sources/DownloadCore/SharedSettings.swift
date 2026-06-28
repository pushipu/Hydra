import Foundation

/// Подмножество настроек, которое нужно расширению (перехват). app — источник
/// правды, пишет в ~/Library/Application Support/Hydra/settings.json, host отдаёт
/// расширению по запросу getSettings.
public struct InterceptSettings: Codable, Sendable {
    public var autoIntercept: Bool
    public var minSizeBytes: Int64
    public var fileTypes: [String]
    public var threadsPerFile: Int
    public var contextMenu: Bool

    public init(autoIntercept: Bool = true,
                minSizeBytes: Int64 = 25 * 1024 * 1024,
                fileTypes: [String] = ["dmg", "zip", "iso", "mp4", "mkv", "pkg", "tar", "gz", "7z"],
                threadsPerFile: Int = 8,
                contextMenu: Bool = true) {
        self.autoIntercept = autoIntercept
        self.minSizeBytes = minSizeBytes
        self.fileTypes = fileTypes
        self.threadsPerFile = threadsPerFile
        self.contextMenu = contextMenu
    }
}

public enum SharedSettings {
    public static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Hydra", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    public static func load() -> InterceptSettings {
        (try? JSONDecoder().decode(InterceptSettings.self, from: Data(contentsOf: fileURL))) ?? InterceptSettings()
    }

    public static func save(_ s: InterceptSettings) {
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: fileURL) }
    }
}
