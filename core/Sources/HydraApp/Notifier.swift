import Foundation
import AppKit

/// Уведомления: завершение, ошибка, требуется вход. Тихий режим глушит «готово»,
/// ошибки/вход — всегда.
///
/// Используем NSUserNotification (а не современный UNUserNotificationCenter)
/// намеренно: UN требует авторизацию, которую служба молча отклоняет для
/// ad-hoc/нестабильно-подписанных локальных сборок («Notifications are not
/// allowed»). Legacy-путь баннеры доставляет без авторизации. Минус — API
/// deprecated; при переходе на нотаризованную сборку можно вернуть UN.
final class Notifier: NSObject, NSUserNotificationCenterDelegate {
    static let shared = Notifier()
    private weak var queue: DownloadQueue?

    func setup(queue: DownloadQueue) {
        self.queue = queue
        NSUserNotificationCenter.default.delegate = self
    }

    @MainActor func notifyDone(filename: String, path: String) {
        if AppSettings.shared.quietMode { return }
        deliver(title: L("Загрузка завершена"), body: filename, action: nil, userInfo: ["path": path])
    }

    @MainActor func notifyFailed(taskId: Int, filename: String, message: String) {
        deliver(title: L("Ошибка загрузки"), body: "\(filename) · \(message)",
                action: L("Повторить"), userInfo: ["taskId": taskId])
    }

    @MainActor func notifyAuthRequired(taskId: Int, filename: String, url: String) {
        let h = URL(string: url)?.host ?? filename
        deliver(title: L("Требуется вход"), body: "\(h) · \(L("сессия истекла во время загрузки"))",
                action: L("Войти"), userInfo: ["taskId": taskId, "url": url])
    }

    private func deliver(title: String, body: String, action: String?, userInfo: [String: Any]) {
        let n = NSUserNotification()
        n.title = title
        n.informativeText = body
        n.soundName = NSUserNotificationDefaultSoundName
        n.userInfo = userInfo
        if let action {
            n.hasActionButton = true
            n.actionButtonTitle = action
        }
        NSUserNotificationCenter.default.deliver(n)
    }

    // Показывать баннер, даже когда app активен.
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent n: NSUserNotification) -> Bool { true }

    // Клик по баннеру или кнопке.
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate n: NSUserNotification) {
        let info = n.userInfo ?? [:]
        let retry = n.activationType == .actionButtonClicked
        Task { @MainActor in
            if retry, let id = info["taskId"] as? Int { self.queue?.retry(id); return }
            if let path = info["path"] as? String {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } else if let u = info["url"] as? String, let url = URL(string: u) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
