import Foundation
import AppKit
import DownloadCore

struct DownloadTask: Identifiable {
    let id: Int
    let url: URL
    var filename: String
    var state: State
    var progress: DownloadProgress?
    var path: String?
    var error: String?
    var startedAt: Date
    var source: TaskSource = .manual   // откуда добавлена загрузка
    var fromHistory = false      // загружено из истории (не показывать в поповере)
    var historyId: String?       // связь с записью HistoryStore для удаления

    enum State { case running, queued, paused, done, failed, cancelled }
}

/// Откуда загрузка попала в очередь.
enum TaskSource: Equatable {
    case manual, drop, clipboard
    case browser(String?)        // домен страницы (Referer), если известен

    /// Иконка SF Symbols для источника.
    var icon: String {
        switch self {
        case .manual:    return "keyboard"
        case .drop:      return "hand.point.up.left"
        case .clipboard: return "doc.on.clipboard"
        case .browser:   return "globe"
        }
    }

    /// Подпись источника (локализованная).
    var label: String {
        switch self {
        case .manual:        return L("Вручную")
        case .drop:          return L("Перетаскивание")
        case .clipboard:     return L("Буфер обмена")
        case .browser(let h): return h ?? L("Браузер")
        }
    }

    /// Строковый токен для персиста (история/мета).
    var token: String {
        switch self {
        case .manual:        return "manual"
        case .drop:          return "drop"
        case .clipboard:     return "clipboard"
        case .browser(let h): return "browser:" + (h ?? "")
        }
    }

    init(token: String) {
        switch token {
        case "manual":    self = .manual
        case "drop":      self = .drop
        case "clipboard": self = .clipboard
        default:
            let h = token.hasPrefix("browser:") ? String(token.dropFirst(8)) : ""
            self = .browser(h.isEmpty ? nil : h)
        }
    }
}

/// Снимок для строки меню, обновляется 1 раз/сек — чтобы статус-айтем не
/// перерисовывался на каждом тике прогресса (10–20 Гц грузят FrontBoard).
@MainActor final class MenuBarModel: ObservableObject {
    @Published var active = 0
    @Published var fraction: Double?
    @Published var pausedOnly = false   // нет активных, но есть на паузе/в очереди
}

@MainActor
class DownloadQueue: ObservableObject {
    let menu = MenuBarModel()
    @Published private(set) var tasks: [DownloadTask] = []
    private var downloads: [Int: ResumableDownload] = [:]
    private var handles: [Int: Task<Void, Never>] = [:]
    private var nextID = 0
    private var sampler: Timer?
    /// Сколько загрузок качаются одновременно; остальные ждут в очереди.
    var maxConcurrent = 4 { didSet { if maxConcurrent > oldValue { promote() } } }
    /// Потоков на файл по умолчанию (ручное добавление по ссылке).
    var defaultConnections = 8

    init() {
        // Раз в секунду обновляем снимок для строки меню (а не на каждом тике прогресса).
        sampler = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMenu() }
        }
    }

    private func refreshMenu() {
        menu.active = active
        menu.fraction = aggregateFraction
        menu.pausedOnly = active == 0 && (pausedCount + queuedCount) > 0
    }

    var active: Int { tasks.filter { $0.state == .running }.count }
    var queuedCount: Int { tasks.filter { $0.state == .queued }.count }
    var pausedCount: Int { tasks.filter { $0.state == .paused }.count }
    var failedCount: Int { tasks.filter { $0.state == .failed }.count }
    var finishedCount: Int { tasks.filter { $0.state == .done }.count }
    var hasHistory: Bool { tasks.contains { $0.fromHistory } }
    var totalSpeed: Double { tasks.compactMap { $0.state == .running ? $0.progress?.bytesPerSecond : nil }.reduce(0, +) }

    /// Для кнопки «Пауза всех»/«Возобновить всё» в подвале.
    func pauseAll() { for t in tasks where t.state == .running { pause(t.id) } }
    func resumeAll() { for t in tasks where t.state == .paused { startOrQueue(t.id) } }

    /// Агрегатный прогресс по активным загрузкам с известным размером (для кольца).
    var aggregateFraction: Double? {
        let known = tasks.compactMap { t -> (Int64, Int64)? in
            guard t.state == .running, let p = t.progress, let total = p.totalBytes else { return nil }
            return (p.receivedBytes, total)
        }
        guard !known.isEmpty else { return nil }
        let rec = known.reduce(Int64(0)) { $0 + $1.0 }
        let tot = known.reduce(Int64(0)) { $0 + $1.1 }
        return tot > 0 ? min(1, Double(rec) / Double(tot)) : nil
    }

    // MARK: - Добавление

    func add(request: DownloadRequest, source: TaskSource? = nil) {
        let d = ResumableDownload.create(request: request)
        // Если источник не задан явно — это перехват из браузера: берём домен из Referer.
        let src = source ?? .browser(request.session.headers["Referer"].flatMap { URL(string: $0)?.host })
        let id = newTask(url: request.url,
                         filename: request.suggestedFilename ?? request.url.lastPathComponent,
                         download: d, source: src)
        startOrQueue(id)
    }

    /// Запустить сразу, если есть свободный слот; иначе — поставить в очередь.
    private func startOrQueue(_ id: Int) {
        if active < maxConcurrent { start(id) }
        else { update(id) { $0.state = .queued } }
    }

    /// Освободился слот — запускаем следующие из очереди (в порядке добавления).
    private func promote() {
        for t in tasks where t.state == .queued {
            if active >= maxConcurrent { break }
            start(t.id)
        }
    }

    /// Добавление по ссылке (поле ввода, перетаскивание, буфер).
    func addURL(_ string: String, source: TaskSource = .manual) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" else { return }
        let dest = AppSettings.shared.defaultDestURL
        add(request: DownloadRequest(url: url, destinationDirectory: dest, maxConnections: defaultConnections),
            source: source)
    }

    // MARK: - Управление

    func start(_ id: Int) {
        guard let d = downloads[id], let idx = idx(id) else { return }
        tasks[idx].state = .running
        tasks[idx].error = nil
        handles[id] = Task { [weak self] in
            do {
                let url = try await d.run { p in
                    Task { @MainActor in self?.update(id) { $0.progress = p; $0.filename = d.currentFilename() } }
                }
                self?.update(id) { $0.state = .done; $0.path = url.path
                    $0.filename = url.lastPathComponent }
                self?.recordHistory(id)
                self?.notifyDone(id)
                self?.promote()
            } catch is CancellationError {
                d.markRunning(false)                    // пауза — состояние выставлено в pause()
                self?.promote()
            } catch {
                if (error as? URLError)?.code == .cancelled {
                    d.markRunning(false)
                } else {
                    let msg = Self.humanError(error)
                    self?.update(id) { $0.state = .failed; $0.error = msg }
                    self?.notifyFailure(id, error: error, message: msg)
                }
                self?.promote()
            }
        }
    }

    /// Записать завершённую загрузку в персистентную историю.
    private func recordHistory(_ id: Int) {
        guard let idx = idx(id), let path = tasks[idx].path else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64).flatMap { $0 } ?? 0
        let entry = HistoryEntry(url: tasks[idx].url, filename: tasks[idx].filename,
                                 path: path, size: size, completedAt: Date(),
                                 origin: tasks[idx].source.token)
        HistoryStore.shared.append(entry)
        tasks[idx].historyId = entry.id
    }

    /// Очистить всю историю скачиваний (и записи на диске, и строки в окне).
    func clearHistory() {
        HistoryStore.shared.clear()
        for t in tasks where t.fromHistory { handles[t.id] = nil; downloads[t.id] = nil }
        tasks.removeAll { $0.fromHistory }
    }

    private func notifyFailure(_ id: Int, error: Error, message: String) {
        guard let t = tasks.first(where: { $0.id == id }) else { return }
        if case let DownloadError.httpStatus(code) = error, code == 401 || code == 403 {
            Notifier.shared.notifyAuthRequired(taskId: id, filename: t.filename, url: t.url.absoluteString)
        } else {
            Notifier.shared.notifyFailed(taskId: id, filename: t.filename, message: message)
        }
    }

    private func notifyDone(_ id: Int) {
        guard let t = tasks.first(where: { $0.id == id }), let path = t.path else { return }
        Notifier.shared.notifyDone(filename: t.filename, path: path)
        // Действие по завершении из настроек.
        switch AppSettings.shared.completionAction {
        case .openFolder: NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .sound:      NSSound(named: "Glass")?.play()
        case .none:       break
        }
    }

    func pause(_ id: Int) {
        guard let idx = idx(id), tasks[idx].state == .running else { return }
        tasks[idx].state = .paused
        handles[id]?.cancel()
        handles[id] = nil
        promote()                                       // освободили слот
    }

    func resume(_ id: Int) { startOrQueue(id) }

    /// Запустить немедленно, не дожидаясь очереди (превышает лимит).
    func forceStart(_ id: Int) { start(id) }

    func retry(_ id: Int) { startOrQueue(id) }

    /// Скачать файл заново: стереть прежний результат и запустить свежую загрузку с того же URL.
    func redownload(_ id: Int) {
        guard let t = tasks.first(where: { $0.id == id }) else { return }
        let dir = t.path.map { URL(fileURLWithPath: $0).deletingLastPathComponent() } ?? AppSettings.shared.defaultDestURL
        let url = t.url, name = t.filename
        if let path = t.path { try? FileManager.default.removeItem(atPath: path) }   // перекачиваем поверх
        remove(id, deleteFile: true)
        add(request: DownloadRequest(url: url, suggestedFilename: name,
                                     destinationDirectory: dir, maxConnections: defaultConnections))
    }

    /// Убрать запись; deleteFile — стереть и недокачанный файл с диска.
    func remove(_ id: Int, deleteFile: Bool = false) {
        if let h = tasks.first(where: { $0.id == id })?.historyId { HistoryStore.shared.remove(h) }
        handles[id]?.cancel(); handles[id] = nil
        downloads[id]?.discard(deleteFile: deleteFile)
        downloads[id] = nil
        tasks.removeAll { $0.id == id }
        promote()
    }

    // MARK: - Восстановление после перезапуска

    /// Демо-данные для скриншотов (включается `defaults write com.hydra.downloads demoMode -bool true`).
    /// ponytail: только для оформления релиза, не трогает реальные загрузки.
    func injectDemoData() {
        let mb: Int64 = 1_048_576
        func blocks(done: Int, active: Int, total: Int) -> [BlockState] {
            (0..<total).map { $0 < done ? .done : ($0 < done + active ? .active : .empty) }
        }
        // Демо-сегменты по потокам для расширенного представления: (нач. МБ, кон. МБ, доля).
        func segs(_ pairs: [(Int64, Int64, Double)]) -> [SegmentInfo] {
            pairs.enumerated().map { i, p in
                let lo = p.0 * mb, hi = p.1 * mb - 1
                return SegmentInfo(id: i, range: lo...hi, received: Int64(Double(hi - lo + 1) * p.2))
            }
        }
        func task(_ url: String, _ name: String, _ state: DownloadTask.State,
                  recv: Int64 = 0, total: Int64? = nil, conns: Int = 0, bps: Double = 0,
                  blk: [BlockState]? = nil, seg: [SegmentInfo]? = nil,
                  path: String? = nil, history: Bool = false, err: String? = nil,
                  source: TaskSource = .manual) -> DownloadTask {
            nextID += 1
            var t = DownloadTask(id: nextID, url: URL(string: url)!, filename: name, state: state, startedAt: Date())
            t.progress = DownloadProgress(totalBytes: total, receivedBytes: recv, connections: conns, bytesPerSecond: bps, blocks: blk, segments: seg)
            t.path = path; t.fromHistory = history; t.error = err; t.source = source
            return t
        }
        tasks = [
            task("https://releases.example.com/macos-sequoia.dmg", "macOS Sequoia.dmg", .running,
                 recv: 1500 * mb, total: 2410 * mb, conns: 6, bps: 23.5 * Double(mb), blk: blocks(done: 156, active: 6, total: 256),
                 seg: segs([(0, 401, 0.93), (401, 803, 0.81), (803, 1205, 0.70),
                            (1205, 1606, 0.58), (1606, 2008, 0.49), (2008, 2410, 0.40)]),
                 source: .browser("developer.apple.com")),
            task("https://data.lab.io/dataset-2024-full.zip", "dataset-2024-full.zip", .queued, total: 4100 * mb,
                 source: .browser("data.lab.io")),
            task("https://cdn.school.edu/lecture-07.mp4", "lecture-07-recording-4k.mp4", .paused,
                 recv: 738 * mb, total: 1800 * mb, conns: 8, blk: blocks(done: 105, active: 0, total: 256),
                 source: .browser("school.edu")),
            task("https://nas.local/backup-2024-06.tar.zst", "backup-2024-06.tar.zst", .failed, err: L("Недостаточно места на диске"),
                 source: .drop),
            task("https://docs.company.com/q3.pdf", "q3-report-final.pdf", .done, recv: 4 * mb, total: 4 * mb, path: "/Users/me/Downloads/q3-report-final.pdf", history: true,
                 source: .browser("docs.company.com")),
            task("https://mega.example/archive.zip", "season-archive-2024.zip", .done, recv: 1100 * mb, total: 1100 * mb, path: "/Users/me/Downloads/season-archive-2024.zip", history: true,
                 source: .clipboard),
            task("https://figma.com/design-assets.fig", "design-assets.fig", .done, recv: 88 * mb, total: 88 * mb, path: "/Users/me/Downloads/design-assets.fig", history: true,
                 source: .manual),
        ]
    }

    func restore() {
        // Недокачанные — восстановить и (если качались) продолжить.
        for meta in DownloadStore.shared.loadAll() {
            let d = ResumableDownload(meta: meta)
            // Источник после перезапуска выводим из сохранённого Referer (если был перехват).
            let src: TaskSource = meta.headers["Referer"].flatMap { URL(string: $0)?.host }.map { .browser($0) } ?? .manual
            let id = newTask(url: meta.url, filename: meta.filename, download: d, source: src)
            update(id) { $0.state = .paused; $0.progress = d.staticProgress() }
            if meta.wasRunning { startOrQueue(id) }
        }
        // История завершённых — как .done строки (видны в окне, не в поповере).
        for h in HistoryStore.shared.load() {
            nextID += 1
            let id = nextID
            var t = DownloadTask(id: id, url: h.url, filename: h.filename, state: .done, startedAt: h.completedAt)
            t.path = h.path
            t.fromHistory = true
            t.historyId = h.id
            t.source = h.origin.map(TaskSource.init(token:)) ?? .manual
            t.progress = DownloadProgress(totalBytes: h.size, receivedBytes: h.size, connections: 0, bytesPerSecond: 0)
            tasks.append(t)
        }
    }

    // MARK: - Внутреннее

    private func newTask(url: URL, filename: String, download: ResumableDownload,
                         source: TaskSource = .manual) -> Int {
        nextID += 1
        let id = nextID
        let name = filename.isEmpty ? "download" : filename
        tasks.append(DownloadTask(id: id, url: url, filename: name, state: .paused,
                                  startedAt: Date(), source: source))
        downloads[id] = download
        return id
    }

    private func idx(_ id: Int) -> Int? { tasks.firstIndex { $0.id == id } }

    private func update(_ id: Int, _ mutate: (inout DownloadTask) -> Void) {
        guard let i = idx(id) else { return }
        mutate(&tasks[i])
    }

    private static func humanError(_ error: Error) -> String {
        switch error {
        case let DownloadError.httpStatus(code): return "HTTP \(code)"
        case DownloadError.unsupportedScheme:    return L("Неподдерживаемая ссылка")
        case DownloadError.rangeNotSatisfiable:  return L("Файл на сервере изменился — нужно заново")
        case DownloadError.insufficientSpace:    return L("Недостаточно места на диске")
        case DownloadError.destinationUnwritable: return L("Папка назначения недоступна для записи")
        case let DownloadError.writeFailed(m):
            return m.localizedCaseInsensitiveContains("space") ? L("Недостаточно места на диске") : m
        case let e as URLError:                  return e.localizedDescription
        default:
            let ns = error as NSError
            // Папка/файл назначения пропали (вынесли/удалили из-под загрузки).
            if (ns.domain == NSCocoaErrorDomain && (ns.code == 4 || ns.code == 260))
                || (ns.domain == NSPOSIXErrorDomain && ns.code == 2) {
                return L("Папка назначения недоступна — нет файла или каталога")
            }
            return ns.localizedDescription   // короткое описание вместо сырого дампа
        }
    }
}
