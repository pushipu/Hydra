import Foundation
import AppKit
import DownloadCore

/// Проверка обновлений через GitHub Releases API (без Sparkle/зависимостей).
/// Сравнивает последний релиз с текущей версией из Info.plist.
@MainActor final class Updater: ObservableObject {
    static let shared = Updater()
    private let repo = "pushipu/Hydra"

    /// Заполнено, если на GitHub есть версия новее текущей.
    @Published var available: (version: String, url: URL)?
    @Published var checking = false

    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// Тихая проверка при запуске: если есть новее — выставляем available и уведомляем один раз.
    func checkOnLaunch() {
        Task {
            if let up = await fetchLatest(), isVersion(up.version, newerThan: current) {
                available = up
                Notifier.shared.notifyUpdate(version: up.version, url: up.url.absoluteString)
            }
        }
    }

    /// Ручная проверка (из меню/настроек): открывает страницу релиза или сообщает «актуально».
    func checkNow() {
        Task {
            checking = true
            let up = await fetchLatest()
            checking = false
            if let up, isVersion(up.version, newerThan: current) {
                available = up
                NSWorkspace.shared.open(up.url)
            } else {
                available = nil
                let a = NSAlert()
                a.messageText = L("У вас актуальная версия")
                a.informativeText = "Hydra \(current)"
                a.runModal()
            }
        }
    }

    private func fetchLatest() async -> (version: String, url: URL)? {
        guard let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Hydra", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let page = (obj["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return (v, page)
    }
}
