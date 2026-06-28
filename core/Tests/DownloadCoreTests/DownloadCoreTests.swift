import XCTest
@testable import DownloadCore

final class DownloadCoreTests: XCTestCase {

    /// Детерминированная нагрузка: байт зависит от позиции, чтобы перепутанные
    /// offset'ы кусков мгновенно ломали сравнение.
    private func makePayload(_ size: Int) -> Data {
        var d = Data(count: size)
        d.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for i in 0..<size {
                p[i] = UInt8(truncatingIfNeeded: (i &* 2654435761) ^ (i >> 3))
            }
        }
        return d
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hydra-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testMultiConnectionDownloadIsByteExact() async throws {
        let payload = makePayload(3 * 1024 * 1024 + 777)   // нечётный размер
        let server = try LoopbackServer(payload: payload, advertiseRanges: true)
        let port = try await server.start()
        defer { server.stop() }

        let dir = try tempDir()
        let req = DownloadRequest(
            url: URL(string: "http://127.0.0.1:\(port)/file.bin")!,
            destinationDirectory: dir,
            maxConnections: 6,
            minChunkSize: 256 * 1024)

        let url = try await Downloader().download(req)
        let got = try Data(contentsOf: url)

        XCTAssertEqual(got.count, payload.count)
        XCTAssertEqual(got, payload, "Содержимое должно совпадать байт-в-байт")
        // probe + несколько кусков → больше одного GET.
        XCTAssertGreaterThan(server.getRequestCount, 2,
                             "Ожидаем несколько параллельных соединений")
    }

    func testFallsBackToSingleStreamWithoutRanges() async throws {
        let payload = makePayload(900 * 1024)
        let server = try LoopbackServer(payload: payload, advertiseRanges: false)
        let port = try await server.start()
        defer { server.stop() }

        let dir = try tempDir()
        let req = DownloadRequest(
            url: URL(string: "http://127.0.0.1:\(port)/file.bin")!,
            destinationDirectory: dir,
            maxConnections: 8,
            minChunkSize: 64 * 1024)

        let url = try await Downloader().download(req)
        let got = try Data(contentsOf: url)
        XCTAssertEqual(got, payload)
    }

    func testSessionHeaderIsReplayed() async throws {
        let payload = makePayload(2 * 1024 * 1024)
        let server = try LoopbackServer(payload: payload, advertiseRanges: true,
                                        requireHeader: (name: "Cookie", value: "session=secret"))
        let port = try await server.start()
        defer { server.stop() }

        let dir = try tempDir()
        let session = SessionContext(cookie: "session=secret",
                                     userAgent: "HydraTest/1.0")
        let req = DownloadRequest(
            url: URL(string: "http://127.0.0.1:\(port)/protected.bin")!,
            session: session,
            destinationDirectory: dir,
            maxConnections: 4,
            minChunkSize: 256 * 1024)

        let url = try await Downloader().download(req)
        let got = try Data(contentsOf: url)
        XCTAssertEqual(got, payload, "Куки должны прокинуться во все потоки")
    }

    func testMissingSessionHeaderFails() async throws {
        let payload = makePayload(512 * 1024)
        let server = try LoopbackServer(payload: payload, advertiseRanges: true,
                                        requireHeader: (name: "Cookie", value: "session=secret"))
        let port = try await server.start()
        defer { server.stop() }

        let dir = try tempDir()
        let req = DownloadRequest(
            url: URL(string: "http://127.0.0.1:\(port)/protected.bin")!,
            destinationDirectory: dir)

        do {
            _ = try await Downloader().download(req)
            XCTFail("Без сессии должно падать с 401")
        } catch let DownloadError.httpStatus(code) {
            XCTAssertEqual(code, 401)
        }
    }

    func testResumableBlockDownloadIsByteExact() async throws {
        // Блочный движок (ResumableDownload) тайлит файл на блоки и собирает их
        // несколькими воркерами — проверяем, что сборка байт-в-байт корректна.
        let payload = makePayload(5 * 1024 * 1024 + 123)   // неровный последний блок
        let server = try LoopbackServer(payload: payload, advertiseRanges: true)
        let port = try await server.start()
        defer { server.stop() }

        let dir = try tempDir()
        let store = DownloadStore(directory: dir.appendingPathComponent("meta"))
        let req = DownloadRequest(
            url: URL(string: "http://127.0.0.1:\(port)/file.bin")!,
            destinationDirectory: dir,
            maxConnections: 6)

        let download = ResumableDownload.create(request: req, store: store)
        let url = try await download.run { _ in }
        let got = try Data(contentsOf: url)

        XCTAssertEqual(got.count, payload.count)
        XCTAssertEqual(got, payload, "Блочная сборка должна совпадать байт-в-байт")
        XCTAssertTrue(store.loadAll().isEmpty, "После завершения мета должна удаляться")
    }

    func testSafeFilenameSanitizes() {
        // Обход каталогов / разделители пути не должны проходить.
        XCTAssertFalse(ResumableDownload.safeFilename("../../etc/passwd").contains("/"))
        XCTAssertFalse(ResumableDownload.safeFilename("a\\b:c").contains(where: { "/\\:".contains($0) }))
        XCTAssertEqual(ResumableDownload.safeFilename(".."), "download")
        XCTAssertEqual(ResumableDownload.safeFilename("."), "download")
        XCTAssertEqual(ResumableDownload.safeFilename(""), "download")
        XCTAssertEqual(ResumableDownload.safeFilename("  отчёт.pdf  "), "отчёт.pdf")
        XCTAssertEqual(ResumableDownload.safeFilename("normal-file.zip"), "normal-file.zip")
        // Длинное имя ограничивается, расширение сохраняется.
        let long = String(repeating: "я", count: 300) + ".dat"   // кириллица = 2 байта/символ
        let capped = ResumableDownload.safeFilename(long)
        XCTAssertLessThanOrEqual(capped.utf8.count, 200)
        XCTAssertTrue(capped.hasSuffix(".dat"))
    }

    func testRateLimiterApproximatesRate() {
        // bucket стартует полным (1000 Б), первые 1000 — бесплатно, следующие 2000
        // при 1000 Б/с должны занять ~2 с.
        let rl = RateLimiter()
        rl.setLimit(bytesPerSecond: 1000)
        let start = Date()
        for _ in 0..<30 { rl.throttle(100) }   // всего 3000 Б
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(elapsed, 1.4, "Лимит должен притормаживать")
        XCTAssertLessThan(elapsed, 4.0)
        // Выключенный лимит — мгновенно.
        rl.setLimit(bytesPerSecond: 0)
        let t2 = Date()
        for _ in 0..<100 { rl.throttle(1_000_000) }
        XCTAssertLessThan(Date().timeIntervalSince(t2), 0.5)
    }

    func testFilenameFromContentDisposition() {
        let info = RemoteFileInfo.filename(
            fromContentDisposition: "attachment; filename=\"report final.pdf\"")
        XCTAssertEqual(info, "report final.pdf")

        let utf = RemoteFileInfo.filename(
            fromContentDisposition: "attachment; filename*=UTF-8''%D0%BE%D1%82%D1%87%D1%91%D1%82.pdf")
        XCTAssertEqual(utf, "отчёт.pdf")
    }

    func testPlanChunksCoversWholeRange() {
        let chunks = Downloader.planChunks(total: 1000, maxConnections: 4, minChunkSize: 100)
        XCTAssertEqual(chunks.first?.0, 0)
        XCTAssertEqual(chunks.last?.1, 999)
        // Непрерывность и отсутствие пересечений.
        for i in 1..<chunks.count {
            XCTAssertEqual(chunks[i].0, chunks[i - 1].1 + 1)
        }
        let covered = chunks.reduce(Int64(0)) { $0 + ($1.1 - $1.0 + 1) }
        XCTAssertEqual(covered, 1000)
    }

    func testVersionComparison() {
        XCTAssertTrue(isVersion("0.2.0", newerThan: "0.1.0"))
        XCTAssertTrue(isVersion("1.0.0", newerThan: "0.9.9"))
        XCTAssertTrue(isVersion("v0.1.1", newerThan: "0.1"))      // ведущая v + разная длина
        XCTAssertFalse(isVersion("0.1.0", newerThan: "0.1.0"))    // равные
        XCTAssertFalse(isVersion("0.1.0", newerThan: "0.2.0"))    // старее
        XCTAssertFalse(isVersion("0.1", newerThan: "0.1.0"))      // 0.1 == 0.1.0
    }
}
