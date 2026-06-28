import AppKit
import SwiftUI
import Combine

/// Своя иконка в строке меню вместо MenuBarExtra: левый клик — попап со списком,
/// правый клик (или ⌃-клик) — контекстное меню. MenuBarExtra правый клик не умеет.
@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let queue: DownloadQueue
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var dropWindow: NSPanel?
    private var cancellable: AnyCancellable?
    private var dropCancellable: AnyCancellable?
    private var pinCancellable: AnyCancellable?

    init(queue: DownloadQueue) {
        self.queue = queue
        super.init()

        popover.behavior = .transient
        // Размер диктует SwiftUI-контент (адаптивная высота под детальный экран,
        // ≤70% экрана) — фиксированный contentSize не ставим, иначе попап не растянется.
        // Действия передаём явно — попап вне SwiftUI-сцен, environment openWindow там не работает.
        let content = ContentView(
            queue: queue,
            onOpenWindow: { [weak self] in self?.popover.performClose(nil); self?.showMainWindow() },
            onOpenSettings: { [weak self] in self?.popover.performClose(nil); self?.showSettings() })
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]   // фитит попап под контент
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateButton()
        // Иконку обновляем по модели (≈1 Гц), после изменения значений.
        cancellable = queue.menu.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateButton() }
        }
        // Видимость плавающего окна — одна настройка (источник правды для меню и
        // окна настроек). Подписка сразу отдаёт текущее значение → восстановление.
        dropCancellable = AppSettings.shared.$dropWindowVisible.sink { [weak self] visible in
            visible ? self?.showDrop() : self?.hideDrop()
        }
        // Пин: закреплённый попап не закрывается по клику снаружи.
        pinCancellable = AppSettings.shared.$popoverPinned.sink { [weak self] pinned in
            self?.popover.behavior = pinned ? .applicationDefined : .transient
        }
    }

    // MARK: Иконка

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let m = queue.menu
        if m.active > 0 {
            button.image = hydraArrowGlyph()
            button.title = m.active == 1 ? (m.fraction.map { " \(Int($0 * 100))%" } ?? "") : " \(m.active)"
            button.imagePosition = .imageLeading
        } else if m.pausedOnly {
            button.image = hydraPauseGlyph(); button.title = ""; button.imagePosition = .imageOnly
        } else {
            button.image = hydraArrowGlyph(); button.title = ""; button.imagePosition = .imageOnly
        }
    }

    // MARK: Клик

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        let menu = NSMenu()
        add(menu, L("Открыть окно загрузок"), #selector(openMain))
        let drop = NSMenuItem(title: L("Окно перетаскивания"), action: #selector(toggleDrop), keyEquivalent: "")
        drop.target = self
        drop.state = AppSettings.shared.dropWindowVisible ? .on : .off
        menu.addItem(drop)
        add(menu, L("Настройки…"), #selector(openSettings), key: ",")
        add(menu, L("Установить расширение…"), #selector(installExtension))
        menu.addItem(.separator())
        if queue.active > 0 {
            add(menu, L("Пауза всех"), #selector(pauseAll))
        } else if queue.pausedCount > 0 {
            add(menu, L("Возобновить всё"), #selector(resumeAll))
        }
        menu.addItem(.separator())
        add(menu, L("Выйти из Hydra"), #selector(quit), key: "q")
        // Штатный показ меню статус-айтема: падает вниз из строки меню, не скроллится.
        // Временно вешаем menu на item, кликаем, снимаем — чтобы ЛКМ остался попапом.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    // MARK: Действия меню

    @objc private func installExtension() { revealBundledExtensions() }
    @objc private func openMain() { showMainWindow() }
    @objc private func openSettings() { showSettings() }
    @objc private func toggleDrop() { AppSettings.shared.dropWindowVisible.toggle() }
    @objc private func pauseAll() { queue.pauseAll() }
    @objc private func resumeAll() { queue.resumeAll() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Главное окно — AppKit-окно (чтобы открывать из меню). Активация дока —
    /// через onAppear/onDisappear внутри MainWindow (WindowActivation).
    private func showMainWindow() {
        if mainWindow == nil {
            let root = MainWindow(queue: queue, onOpenSettings: { [weak self] in self?.showSettings() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = L("Загрузки")
            w.setContentSize(NSSize(width: 900, height: 580))
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            mainWindow = w
        }
        present(mainWindow)
    }

    /// Окно настроек — тоже AppKit (сцена SwiftUI Settings в accessory-режиме не
    /// регистрирует действие showSettingsWindow:, поэтому открываем сами).
    private func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(queue: queue)))
            w.title = L("Настройки Hydra")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        present(settingsWindow)
    }

    /// Плавающее окно-приёмник: поверх всех окон, через все спейсы, без активации.
    private func showDrop() {
        if dropWindow == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 150, height: 150),
                                styleMask: [.nonactivatingPanel, .borderless],
                                backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            // Крестик идёт через ту же настройку — иначе меню/настройки рассинхронятся.
            panel.contentView = NSHostingView(
                rootView: DropTargetView(queue: queue, onClose: { AppSettings.shared.dropWindowVisible = false }))
            panel.setFrameAutosaveName("HydraDropPanel")   // запоминаем позицию
            panel.setContentSize(NSSize(width: 150, height: 150))   // autosave мог вернуть старый размер
            if panel.frame.origin == .zero {
                if let vf = NSScreen.main?.visibleFrame {
                    panel.setFrameOrigin(NSPoint(x: vf.maxX - 150, y: vf.maxY - 150))
                }
            }
            dropWindow = panel
        }
        dropWindow?.orderFrontRegardless()
    }

    private func hideDrop() {
        dropWindow?.orderOut(nil)
    }

    private func present(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)   // иконка в доке, ⌘-Tab, меню — пока окно открыто
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // Закрыли окно — если ни одного нашего окна не осталось, снова только строка меню.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let anyVisible = [self.mainWindow, self.settingsWindow].contains { $0?.isVisible == true }
            NSApp.setActivationPolicy(anyVisible ? .regular : .accessory)
        }
    }
}
