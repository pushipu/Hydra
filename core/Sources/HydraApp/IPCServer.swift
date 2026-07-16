import Foundation
import DownloadCore

extension Notification.Name {
    static let hydraOpenMain = Notification.Name("HydraOpenMain")
}

/// Факт связки с браузерным расширением: хост шлёт «hello» при пинге из попапа.
/// Используется онбордингом/настройками для живой проверки «расширение связано».
@MainActor final class Pairing: ObservableObject {
    static let shared = Pairing()
    @Published var seenExtension = false
    func markSeen() { seenExtension = true }
}

// ponytail: BSD sockets проще Network framework для Unix domain socket
class IPCServer {
    private let socketPath = "/tmp/hydra.sock"

    func start(queue: DownloadQueue) async {
        Task.detached { [weak queue, socketPath] in
            try? FileManager.default.removeItem(atPath: socketPath)
            guard let sock = Self.listenSocket(socketPath) else { return }
            defer { close(sock) }

            while let client = Self.acceptClient(sock) {
                Task { @MainActor in
                    guard let queue else { return }
                    await Self.handle(client, queue: queue)
                }
            }
        }
    }

    private static func listenSocket(_ path: String) -> Int32? {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            path.withCString { strncpy(ptr.baseAddress!, $0, ptr.count) }
        }
        let len = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + path.utf8.count + 1)
        guard withUnsafePointer(to: &addr, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, len) }
        }) == 0, Darwin.listen(sock, 128) == 0 else { close(sock); return nil }
        return sock
    }

    private static func acceptClient(_ sock: Int32) -> FileHandle? {
        let client = Darwin.accept(sock, nil, nil)
        return client >= 0 ? FileHandle(fileDescriptor: client, closeOnDealloc: true) : nil
    }

    private static func handle(_ fh: FileHandle, queue: DownloadQueue) async {
        var buffer = Data()
        while let chunk = try? fh.read(upToCount: 4096), !chunk.isEmpty {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer = buffer.suffix(from: buffer.index(after: newline))
                guard let msg = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                // «hello» — пинг попапа расширения через host: фиксируем связку.
                if msg["type"] as? String == "hello" { await MainActor.run { Pairing.shared.markSeen() }; continue }
                if msg["type"] as? String == "openMain" {
                    await MainActor.run { NotificationCenter.default.post(name: .hydraOpenMain, object: nil) }
                    continue
                }
                if msg["type"] as? String == "setSettings" {
                    let auto = msg["autoIntercept"] as? Bool
                    let minSize = (msg["minSizeMB"] as? NSNumber)?.intValue
                    let threads = (msg["threadsPerFile"] as? NSNumber)?.intValue
                    await MainActor.run {
                        AppSettings.shared.applyInterceptSettings(
                            autoIntercept: auto, minSizeMB: minSize, threadsPerFile: threads)
                    }
                    continue
                }
                guard msg["type"] as? String == "download",
                      let urlString = msg["url"] as? String, let url = URL(string: urlString) else { continue }
                let session = SessionContext(
                    cookie: msg["cookie"] as? String,
                    userAgent: msg["userAgent"] as? String,
                    referer: msg["referer"] as? String,
                    extra: (msg["headers"] as? [String: String]) ?? [:])
                let destPath = (msg["destination"] as? String) ?? (NSHomeDirectory() + "/Downloads")
                let request = DownloadRequest(
                    url: url, session: session,
                    suggestedFilename: msg["filename"] as? String,
                    destinationDirectory: URL(fileURLWithPath: destPath, isDirectory: true),
                    maxConnections: (msg["connections"] as? Int) ?? 8)
                await MainActor.run { queue.add(request: request) }
            }
        }
        try? fh.close()
    }
}
