import Foundation
import DownloadCore

/// Native messaging host: браузер запускает бинарь и общается фреймами (4 байта
/// длины, native byte order + UTF-8 JSON). Входящие type: ping / getDownloads /
/// getSettings / download. Загрузку делегируем в Hydra.app через /tmp/hydra.sock;
/// если app не запущен — качаем локально.
@main
struct Host {
    static func main() async {
        let io = NativeMessagingIO()

        while let message = io.readMessage() {
            let type = message["type"] as? String
            // Пинг от popup расширения: жив ли Hydra.app (просто пробуем подключиться).
            if type == "ping" {
                io.send(["type": "status", "connected": Self.sayHello()])
                continue
            }
            // Снимок активных/паузных загрузок для попапа (читаем меты с диска —
            // без записи app→сокет, которая шлёт EPIPE).
            if type == "getDownloads" {
                if UserDefaults(suiteName: "com.hydra.downloads")?.bool(forKey: "demoMode") == true {
                    io.send(["type": "downloads", "items": Self.demoDownloads()])   // моки для скриншота
                    continue
                }
                let items = DownloadStore.shared.loadAll().map { m -> [String: Any] in
                    ["name": m.filename, "total": m.total, "done": m.completedBytes, "running": m.wasRunning]
                }
                io.send(["type": "downloads", "items": items])
                continue
            }
            // Настройки перехвата — app источник правды, читаем из общего settings.json.
            if type == "getSettings" {
                let s = SharedSettings.load()
                io.send(["type": "settings",
                         "autoIntercept": s.autoIntercept,
                         "minSizeBytes": s.minSizeBytes,
                         "fileTypes": s.fileTypes,
                         "threadsPerFile": s.threadsPerFile,
                         "contextMenu": s.contextMenu])
                continue
            }
            guard type == "download" else {
                io.send(["type": "error", "message": "unknown type"])
                continue
            }
            // ponytail: отправляем в Hydra.app; если не работает — качаем сами
            if Self.delegate(message) {
                io.send(["type": "done", "message": "delegated to Hydra.app"])
            } else {
                await Self.downloadLocally(message, io: io)
            }
        }
    }

    private static func demoDownloads() -> [[String: Any]] {
        let mb: Int64 = 1_048_576
        return [
            ["name": "macOS Sequoia.dmg", "total": 2410 * mb, "done": 1500 * mb, "running": true],
            ["name": "dataset-2024-full.zip", "total": 4100 * mb, "done": 0, "running": false],
            ["name": "lecture-07-recording-4k.mp4", "total": 1800 * mb, "done": 738 * mb, "running": false],
        ]
    }

    /// Подключиться к сокету Hydra.app; nil — app не слушает. Дескриптор закрывает вызывающий.
    private static func connectSocket() -> Int32? {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = "/tmp/hydra.sock"
        _ = withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            path.withCString { strncpy(ptr.baseAddress!, $0, ptr.count) }
        }
        let len = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + path.utf8.count + 1)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(sock, $0, len) }
        } == 0
        if !ok { close(sock); return nil }
        return sock
    }

    /// Пинг попапа: сообщаем app о себе («hello») и заодно проверяем, что он жив.
    private static func sayHello() -> Bool { delegate(["type": "hello"]) }

    private static func delegate(_ msg: [String: Any]) -> Bool {
        guard let sock = connectSocket() else { return false }
        defer { close(sock) }
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return false }
        var payload = data
        payload.append(10) // newline
        return payload.withUnsafeBytes { Darwin.write(sock, $0.baseAddress!, payload.count) } == payload.count
    }

    private static func downloadLocally(_ message: [String: Any], io: NativeMessagingIO) async {
        guard let urlString = message["url"] as? String, let url = URL(string: urlString) else {
            io.send(["type": "error", "message": "bad url"])
            return
        }
        let session = SessionContext(
            cookie: message["cookie"] as? String,
            userAgent: message["userAgent"] as? String,
            referer: message["referer"] as? String,
            extra: (message["headers"] as? [String: String]) ?? [:])
        let destPath = (message["destination"] as? String) ?? (NSHomeDirectory() + "/Downloads")
        let request = DownloadRequest(
            url: url, session: session,
            suggestedFilename: message["filename"] as? String,
            destinationDirectory: URL(fileURLWithPath: destPath, isDirectory: true),
            maxConnections: (message["connections"] as? Int) ?? 8)

        do {
            let result = try await Downloader().download(request)
            io.send(["type": "done", "path": result.path])
        } catch {
            io.send(["type": "error", "message": "\(error)"])
        }
    }
}

/// Чтение/запись фреймов native messaging со stdin/stdout.
final class NativeMessagingIO: @unchecked Sendable {
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput
    private let writeLock = NSLock()

    func readMessage() -> [String: Any]? {
        guard let lenData = readExact(4) else { return nil }
        let length = lenData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard length > 0, length < 64 * 1024 * 1024 else { return nil }
        guard let body = readExact(Int(length)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    private func readExact(_ n: Int) -> Data? {
        var acc = Data()
        while acc.count < n {
            let chunk = input.readData(ofLength: n - acc.count)
            if chunk.isEmpty { return nil }   // EOF
            acc.append(chunk)
        }
        return acc
    }

    func send(_ message: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: message) else { return }
        var length = UInt32(body.count)
        var frame = Data(bytes: &length, count: 4)
        frame.append(body)
        writeLock.lock(); defer { writeLock.unlock() }
        output.write(frame)
    }
}
