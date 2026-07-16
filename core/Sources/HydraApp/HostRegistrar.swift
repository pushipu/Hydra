import Foundation

/// Само-регистрация native messaging host при запуске Hydra.app — заменяет
/// ручной `install.sh`. Браузер запускает host (`com.hydra.host`) только если в
/// его каталоге NativeMessagingHosts лежит манифест, указывающий на бинарь.
/// Hydra.app пишет эти манифесты сам, указывая на host, вложенный в .app.
///
/// Chrome/Brave/Edge используют один и тот же extension id, потому что он
/// детерминированно выводится из `key` в manifest.chrome.json (см. ниже).
/// Firefox опознаёт расширение по gecko-id из манифеста.
enum HostRegistrar {
    /// Детерминированный id Chrome-расширения, выведенный из публичного ключа в
    /// extension/manifest.chrome.json. Меняешь ключ — обнови и это значение
    /// (./build-all.sh печатает актуальный id при сборке).
    static let chromeExtensionID = "hfdmeoleepighofjiookfjcjekoopaim"
    static let firefoxExtensionID = "hydra@pushipu.github.io"
    static let hostName = "com.hydra.host"

    /// Путь к бинарю host. В собранном .app он лежит в Contents/Resources;
    /// при `swift run` — рядом с исполняемым HydraApp в .build/<conf>/.
    static func hostBinaryPath() -> String? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("hydra-host"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("hydra-host"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }?.path
    }

    /// Браузеры на macOS: (базовый каталог профиля, стиль allowed_*-поля).
    /// Манифест пишем только если базовый каталог браузера существует —
    /// значит браузер установлен, не мусорим под остальные.
    private static func targets() -> [(base: String, chromeStyle: Bool)] {
        let support = NSHomeDirectory() + "/Library/Application Support"
        return [
            ("\(support)/Google/Chrome", true),
            ("\(support)/Chromium", true),
            ("\(support)/BraveSoftware/Brave-Browser", true),
            ("\(support)/Microsoft Edge", true),
            ("\(support)/Mozilla", false),
        ]
    }

    static func registerAll() {
        guard let host = hostBinaryPath() else {
            NSLog("Hydra: hydra-host не найден рядом с приложением — регистрация пропущена")
            return
        }
        let fm = FileManager.default
        for t in targets() where fm.fileExists(atPath: t.base) {
            let dir = t.base + "/NativeMessagingHosts"
            let dest = dir + "/\(hostName).json"
            var manifest: [String: Any] = [
                "name": hostName,
                "description": "Hydra multithreaded download manager native host",
                "path": host,
                "type": "stdio",
            ]
            if t.chromeStyle {
                manifest["allowed_origins"] = ["chrome-extension://\(chromeExtensionID)/"]
            } else {
                manifest["allowed_extensions"] = [firefoxExtensionID]
            }
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: URL(fileURLWithPath: dest))
            } catch {
                NSLog("Hydra: не удалось записать host-манифест \(dest): \(error)")
            }
        }
    }
}
