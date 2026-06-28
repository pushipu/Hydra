import Foundation

/// Блочная загрузка с паузой/резюмом. Файл бьётся на блоки; пул из N соединений
/// тянет блоки из общей очереди. Готовые блоки помечаются в битовой карте, которая
/// пишется на диск (DownloadStore) — поэтому загрузка переживает паузу и перезапуск.
///
/// `run` крутится до полной готовности (возвращает URL итогового файла), бросает
/// `CancellationError` при паузе (через отмену Swift-таска) и обычную ошибку при сбое.
public final class ResumableDownload: @unchecked Sendable {
    public private(set) var meta: DownloadMeta
    private let store: DownloadStore
    private let urlSession: URLSession

    private let lock = NSLock()
    private var inFlight: Set<Int> = []
    private var received: Int64 = 0
    private var runStartReceived: Int64 = 0
    private var runStart = Date()
    private var segments: [Int: SegmentInfo] = [:]
    private var lastEmit = Date.distantPast
    private var onProgress: (@Sendable (DownloadProgress) -> Void)?

    public var id: String { meta.id }

    static let minBlock: Int64 = 512 * 1024

    public init(meta: DownloadMeta, store: DownloadStore = .shared, urlSession: URLSession? = nil) {
        self.meta = meta
        self.store = store
        self.urlSession = urlSession ?? Self.makeSession()
    }

    /// Свежая загрузка из запроса (probe и инициализация — внутри `run`).
    public static func create(request: DownloadRequest, store: DownloadStore = .shared) -> ResumableDownload {
        let raw = (request.suggestedFilename ?? request.url.lastPathComponent).removingPercentEncoding
            ?? (request.suggestedFilename ?? request.url.lastPathComponent)
        let name = safeFilename(raw)
        let meta = DownloadMeta(
            id: UUID().uuidString, url: request.url, filename: name,
            destinationDir: request.destinationDirectory, partPath: "",
            total: 0, blockSize: 0, doneBlocks: [], etag: nil,
            headers: request.session.headers, connections: request.maxConnections,
            wasRunning: false, createdAt: Date())
        return ResumableDownload(meta: meta, store: store)
    }

    static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpMaximumConnectionsPerHost = 16
        // Concurrent delegate-очередь — чтобы сон троттлинга в didReceive не сериализовал потоки.
        let dq = OperationQueue(); dq.maxConcurrentOperationCount = 16
        return URLSession(configuration: cfg, delegate: nil, delegateQueue: dq)
    }

    /// Потокобезопасное имя для отображения (уточняется после probe).
    public func currentFilename() -> String { lock.lock(); defer { lock.unlock() }; return meta.filename }

    /// Уточняет имя файла из Content-Disposition / редиректнутого URL — один раз,
    /// на свежей загрузке (на резюме имя уже зафиксировано в partPath).
    private func refineFilenameFresh(info: RemoteFileInfo) {
        let better: String
        if let cd = info.suggestedFilename, !cd.isEmpty {
            better = Self.safeFilename(cd)               // приоритет — Content-Disposition
        } else {
            let current = meta.filename
            let weak = current == "download" || (current as NSString).pathExtension.isEmpty
            let last = info.url.lastPathComponent        // финальный (после редиректов) URL
            if weak, !last.isEmpty, last != "/", !(last as NSString).pathExtension.isEmpty {
                better = Self.safeFilename(last.removingPercentEncoding ?? last)
            } else {
                better = current
            }
        }
        guard better != meta.filename else { return }
        lock.lock(); meta.filename = better; lock.unlock()
    }

    /// Безопасное имя файла: без разделителей пути и обхода каталогов, без
    /// ведущих/хвостовых точек и пробелов, ограниченной длины (255 байт — лимит ФС).
    public static func safeFilename(_ raw: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:\0")
        var name = raw.components(separatedBy: bad).joined(separator: "_")
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " .\t\r\n"))
        if name.isEmpty || name == "." || name == ".." { return "download" }
        return capBytes(name, max: 200)   // запас под .hydrapart и « (N)»
    }

    private static func capBytes(_ s: String, max: Int) -> String {
        guard s.utf8.count > max else { return s }
        let ns = s as NSString
        let ext = ns.pathExtension
        let extPart = ext.isEmpty ? "" : "." + ext
        var stem = ns.deletingPathExtension
        while !stem.isEmpty && (stem + extPart).utf8.count > max { stem.removeLast() }
        return stem.isEmpty ? "download" : stem + extPart
    }

    /// Помечает «качалось» (для авто-резюма при старте) и сохраняет.
    public func markRunning(_ running: Bool) {
        guard !meta.doneBlocks.isEmpty else { return }
        lock.lock(); meta.wasRunning = running; let m = meta; lock.unlock()
        store.save(m)
    }

    /// Статичный снимок прогресса из битовой карты (для восстановленных/паузных
    /// загрузок, у которых ещё нет живого прогресса). nil — если не блочная.
    public func staticProgress() -> DownloadProgress? {
        guard !meta.doneBlocks.isEmpty else { return nil }
        var blocks = [BlockState](repeating: .empty, count: meta.doneBlocks.count)
        for i in meta.doneBlocks.indices where meta.doneBlocks[i] { blocks[i] = .done }
        return DownloadProgress(totalBytes: meta.total, receivedBytes: meta.completedBytes,
                                connections: 0, bytesPerSecond: 0, blocks: blocks, segments: [])
    }

    /// Удаляет запись (и, опционально, недокачанный файл с диска).
    public func discard(deleteFile: Bool) {
        store.delete(meta.id)
        if deleteFile, !meta.partPath.isEmpty {
            try? FileManager.default.removeItem(atPath: meta.partPath)
        }
    }

    // MARK: - Запуск

    public func run(onProgress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        self.onProgress = onProgress
        // Папка назначения могла исчезнуть (вынесли/удалили) — гарантируем её,
        // иначе preallocate/запись падают «No such file or directory».
        do { try FileManager.default.createDirectory(at: meta.destinationDir, withIntermediateDirectories: true) }
        catch { throw DownloadError.destinationUnwritable }
        guard FileManager.default.isWritableFile(atPath: meta.destinationDir.path) else {
            throw DownloadError.destinationUnwritable
        }
        let ctx = SessionContext(headers: meta.headers)
        let info = try await HeaderProbe.probe(url: meta.url, session: ctx, urlSession: urlSession)

        let canBlock = info.acceptsRanges
            && (info.contentLength ?? 0) >= Self.minBlock * 2
            && meta.connections > 1

        if meta.total == 0 {
            // первичная инициализация
            refineFilenameFresh(info: info)   // подтянуть имя из Content-Disposition/редиректа
            // Хватит ли места на диске (проверяем до старта, на свежей загрузке).
            if let total = info.contentLength, total > 0, !Self.hasFreeSpace(meta.destinationDir, need: total) {
                throw DownloadError.insufficientSpace(needBytes: total)
            }
            guard canBlock, let total = info.contentLength else {
                return try await singleStream(info: info, ctx: ctx)
            }
            let partPath = setupBlocks(total: total, info: info)
            try Downloader.preallocate(at: URL(fileURLWithPath: partPath), size: total)
        } else {
            // резюм: ресурс не должен был измениться
            if let e = meta.etag, let cur = info.etag, e != cur { throw DownloadError.rangeNotSatisfiable }
            if let len = info.contentLength, len != meta.total { throw DownloadError.rangeNotSatisfiable }
            if !info.acceptsRanges { throw DownloadError.rangeNotSatisfiable }
            if !partFileOK() {   // partfile пропал/побит — качаем заново
                try Downloader.preallocate(at: URL(fileURLWithPath: meta.partPath), size: meta.total)
                resetBitmap()
            }
        }

        beginRun()   // затравка прогресса от готовых блоков + пометка «качается» на диск

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                let n = min(meta.connections, meta.doneBlocks.count)
                for w in 0..<n { group.addTask { try await self.worker(w, info: info, ctx: ctx) } }
                try await group.waitForAll()
            }
        } catch DownloadError.httpStatus(200) {
            // Сервер солгал про Range (206 на probe, но 200 на реальный диапазон) —
            // partfile побит, откатываемся в честный один поток.
            store.delete(meta.id)
            lock.lock(); meta.total = 0; meta.doneBlocks = []; lock.unlock()
            return try await singleStream(info: info, ctx: ctx)
        }

        try Task.checkCancellation()
        return try finalize()
    }

    // MARK: - Воркер

    private func worker(_ wid: Int, info: RemoteFileInfo, ctx: SessionContext) async throws {
        while true {
            try Task.checkCancellation()
            guard let i = claimNextBlock(worker: wid) else { return }
            let (start, end) = meta.blockRange(i)
            do {
                let fh = try FileHandle(forWritingTo: URL(fileURLWithPath: meta.partPath))
                defer { try? fh.close() }
                try fh.seek(toOffset: UInt64(start))
                let cd = ChunkDownloader(fileHandle: fh, ranged: true,
                                         onBytes: { [weak self] n in self?.addBytes(n, worker: wid) })
                try await cd.run(url: info.url, range: (start, end), session: ctx, urlSession: urlSession)
                completeBlock(i, worker: wid)
            } catch {
                releaseBlock(i, worker: wid)
                throw error
            }
        }
    }

    // MARK: - Учёт блоков (под локом — синхронные методы, NSLock легален)

    private func setupBlocks(total: Int64, info: RemoteFileInfo) -> String {
        let bs = Self.chooseBlockSize(total)
        let count = Int((total + bs - 1) / bs)
        lock.lock()
        meta.total = total; meta.blockSize = bs
        meta.doneBlocks = Array(repeating: false, count: count)
        meta.etag = info.etag
        meta.partPath = meta.destinationDir.appendingPathComponent(meta.filename + ".hydrapart").path
        let m = meta
        lock.unlock()
        store.save(m)
        return m.partPath
    }

    private func resetBitmap() {
        lock.lock(); for i in meta.doneBlocks.indices { meta.doneBlocks[i] = false }; lock.unlock()
    }

    private func beginRun() {
        lock.lock()
        meta.wasRunning = true
        received = meta.completedBytes
        runStartReceived = received
        runStart = Date()
        let m = meta
        lock.unlock()
        store.save(m)
    }

    private func claimNextBlock(worker: Int) -> Int? {
        lock.lock(); defer { lock.unlock() }
        for i in meta.doneBlocks.indices where !meta.doneBlocks[i] && !inFlight.contains(i) {
            inFlight.insert(i)
            let (s, e) = meta.blockRange(i)
            segments[worker] = SegmentInfo(id: worker, range: s...e, received: 0)
            return i
        }
        return nil
    }

    private func completeBlock(_ i: Int, worker: Int) {
        lock.lock()
        meta.doneBlocks[i] = true
        inFlight.remove(i)
        segments[worker] = nil
        let m = meta
        lock.unlock()
        store.save(m)       // персист битовой карты — переживает перезапуск
    }

    private func releaseBlock(_ i: Int, worker: Int) {
        lock.lock(); inFlight.remove(i); segments[worker] = nil; lock.unlock()
    }

    private func addBytes(_ n: Int64, worker: Int) {
        lock.lock()
        received += n
        let now = Date()
        if var seg = segments[worker] {
            seg.received += n
            segments[worker] = seg
        }
        let emit = now.timeIntervalSince(lastEmit) >= 0.1
        if emit { lastEmit = now }
        let snapshot = emit ? snapshotLocked(now) : nil
        lock.unlock()
        if let snapshot { onProgress?(snapshot) }
    }

    private func snapshotLocked(_ now: Date) -> DownloadProgress {
        var blocks = [BlockState](repeating: .empty, count: meta.doneBlocks.count)
        for i in meta.doneBlocks.indices { if meta.doneBlocks[i] { blocks[i] = .done } }
        for i in inFlight { blocks[i] = .active }
        let elapsed = max(0.001, now.timeIntervalSince(runStart))
        let bps = Double(received - runStartReceived) / elapsed
        return DownloadProgress(totalBytes: meta.total, receivedBytes: received,
                                connections: inFlight.count, bytesPerSecond: bps,
                                blocks: blocks, segments: segments.values.sorted { $0.id < $1.id })
    }

    // MARK: - Завершение / одно-поточный фолбэк

    private func finalize() throws -> URL {
        let fm = FileManager.default
        // partfile должен быть на месте (его могли удалить/перенести).
        guard fm.fileExists(atPath: meta.partPath) else { throw DownloadError.writeFailed("временный файл исчез") }
        let finalURL = Downloader.uniqueDestination(directory: meta.destinationDir, filename: meta.filename)
        if fm.fileExists(atPath: finalURL.path) { try? fm.removeItem(at: finalURL) }
        do {
            try fm.moveItem(at: URL(fileURLWithPath: meta.partPath), to: finalURL)
        } catch {
            // partfile НЕ удаляем — останется для повтора/резюма.
            throw DownloadError.writeFailed("не удалось сохранить «\(finalURL.lastPathComponent)»: \((error as NSError).localizedDescription)")
        }
        store.delete(meta.id)
        return finalURL
    }

    private func singleStream(info: RemoteFileInfo, ctx: SessionContext) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: meta.destinationDir, withIntermediateDirectories: true)
        let partURL = meta.destinationDir.appendingPathComponent(meta.filename + ".hydrapart")
        fm.createFile(atPath: partURL.path, contents: nil)
        runStart = Date()
        do {
            let fh = try FileHandle(forWritingTo: partURL)
            defer { try? fh.close() }
            let cd = ChunkDownloader(fileHandle: fh, ranged: false,
                                     onBytes: { [weak self] n in self?.addSingle(n, total: info.contentLength) })
            try await cd.run(url: info.url, range: nil, session: ctx, urlSession: urlSession)
        } catch {
            try? fm.removeItem(at: partURL)
            throw error
        }
        let finalURL = Downloader.uniqueDestination(directory: meta.destinationDir, filename: meta.filename)
        if fm.fileExists(atPath: finalURL.path) { try? fm.removeItem(at: finalURL) }
        try fm.moveItem(at: partURL, to: finalURL)
        return finalURL
    }

    private func addSingle(_ n: Int64, total: Int64?) {
        lock.lock()
        received += n
        let now = Date()
        let emit = now.timeIntervalSince(lastEmit) >= 0.1
        if emit { lastEmit = now }
        let r = received
        let bps = Double(received) / max(0.001, now.timeIntervalSince(runStart))
        lock.unlock()
        if emit { onProgress?(DownloadProgress(totalBytes: total, receivedBytes: r, connections: 1, bytesPerSecond: bps)) }
    }

    // MARK: - Вспомогательное

    /// Достаточно ли свободного места под файл (с запасом 50 МБ).
    static func hasFreeSpace(_ dir: URL, need: Int64) -> Bool {
        if let vals = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let avail = vals.volumeAvailableCapacityForImportantUsage {
            return avail > need + 50 * 1024 * 1024
        }
        return true   // не смогли узнать — не блокируем
    }

    private func partFileOK() -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: meta.partPath)
        return (attrs?[.size] as? Int64) == meta.total
    }

    /// Размер блока под ~256 кубиков, в пределах [512 KB, 16 MB], кратно 256 KB.
    static func chooseBlockSize(_ total: Int64) -> Int64 {
        let q: Int64 = 256 * 1024
        var bs = total / 256
        bs = max(minBlock, min(bs, 16 * 1024 * 1024))
        bs = max(q, (bs / q) * q)
        return bs
    }
}
