import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let queue = DownloadQueue()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Запись в закрытый сокет (ответ на ping) шлёт SIGPIPE и убивает процесс — глушим.
        signal(SIGPIPE, SIG_IGN)
        // macOS усыпляет menu-bar app без окон и убивает с фоновыми загрузками — запрещаем.
        ProcessInfo.processInfo.disableAutomaticTermination("Hydra качает в фоне")
        ProcessInfo.processInfo.disableSuddenTermination()

        AppSettings.shared.bind(to: queue)   // настройки → очередь (лимит одновременности и т.п.)
        HostRegistrar.registerAll()
        Notifier.shared.setup(queue: queue)
        Task { await IPCServer().start(queue: queue) }
        if UserDefaults.standard.bool(forKey: "demoMode") { queue.injectDemoData() }   // моки для скриншотов
        else { queue.restore() }
        statusBar = StatusBarController(queue: queue)   // иконка строки меню + ПКМ-меню
        if !UserDefaults.standard.bool(forKey: "demoMode") { Updater.shared.checkOnLaunch() }
    }
}

@main
struct HydraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Вся видимая часть (иконка строки меню, попап, окна загрузок и настроек) —
        // AppKit в StatusBarController, чтобы работал правый клик и открытие окон из
        // accessory-режима. Сцена Settings нужна лишь чтобы App имел хотя бы один Scene.
        Settings { EmptyView() }
    }
}
