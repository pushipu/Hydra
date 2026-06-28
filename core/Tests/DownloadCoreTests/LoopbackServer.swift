import Foundation
import Network

/// Минимальный HTTP/1.1 сервер на loopback для тестов: GET/HEAD, Range → 206,
/// опциональная проверка обязательного заголовка (имитация авторизации).
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let payload: Data
    private let advertiseRanges: Bool
    private let requireHeader: (name: String, value: String)?
    private let queue = DispatchQueue(label: "hydra.loopback")

    private let lock = NSLock()
    private var _getCount = 0
    private var _readyPort: UInt16?

    var getRequestCount: Int { lock.lock(); defer { lock.unlock() }; return _getCount }

    init(payload: Data,
         advertiseRanges: Bool = true,
         requireHeader: (name: String, value: String)? = nil) throws {
        self.payload = payload
        self.advertiseRanges = advertiseRanges
        self.requireHeader = requireHeader
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        self.listener = try NWListener(using: params)
    }

    /// Запускает сервер и возвращает выбранный порт.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            let resumed = NSLock()
            var done = false
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = self?.listener.port?.rawValue ?? 0
                    resumed.lock()
                    if !done { done = true; resumed.unlock(); cont.resume(returning: port) }
                    else { resumed.unlock() }
                case .failed(let err):
                    resumed.lock()
                    if !done { done = true; resumed.unlock(); cont.resume(throwing: err) }
                    else { resumed.unlock() }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    // MARK: - Обработка соединения

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveRequest(conn, buffer: Data())
    }

    private func receiveRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var acc = buffer
            if let data { acc.append(data) }
            if let headerEnd = acc.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = acc.subdata(in: acc.startIndex..<headerEnd.lowerBound)
                self.respond(conn, headerText: String(decoding: headerData, as: UTF8.self))
                return
            }
            if error != nil || isComplete { conn.cancel(); return }
            self.receiveRequest(conn, buffer: acc)
        }
    }

    private func respond(_ conn: NWConnection, headerText: String) {
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { conn.cancel(); return }
        let parts = requestLine.components(separatedBy: " ")
        let method = parts.first ?? "GET"

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        // Имитация авторизации: требуемый заголовок отсутствует/не совпал → 401.
        if let req = requireHeader {
            if headers[req.name.lowercased()] != req.value {
                send(conn, status: "401 Unauthorized", headers: [:], body: Data("unauthorized".utf8), method: method)
                return
            }
        }

        if method == "GET" {
            lock.lock(); _getCount += 1; lock.unlock()
        }

        let total = payload.count
        var responseHeaders: [String: String] = [
            "Content-Type": "application/octet-stream",
            "ETag": "\"test-etag\"",
        ]
        if advertiseRanges {
            responseHeaders["Accept-Ranges"] = "bytes"
        }

        // Разбор Range.
        if advertiseRanges, let rangeHeader = headers["range"],
           let (start, end) = parseRange(rangeHeader, total: total) {
            let slice = payload.subdata(in: start..<(end + 1))
            responseHeaders["Content-Range"] = "bytes \(start)-\(end)/\(total)"
            send(conn, status: "206 Partial Content", headers: responseHeaders, body: slice, method: method)
        } else {
            send(conn, status: "200 OK", headers: responseHeaders, body: payload, method: method)
        }
    }

    private func parseRange(_ header: String, total: Int) -> (Int, Int)? {
        guard let eq = header.firstIndex(of: "=") else { return nil }
        let spec = header[header.index(after: eq)...]
        let comps = spec.components(separatedBy: "-")
        guard comps.count == 2 else { return nil }
        let startStr = comps[0].trimmingCharacters(in: .whitespaces)
        let endStr = comps[1].trimmingCharacters(in: .whitespaces)
        guard let start = Int(startStr), start < total else { return nil }
        let end = endStr.isEmpty ? total - 1 : min(Int(endStr) ?? (total - 1), total - 1)
        guard end >= start else { return nil }
        return (start, end)
    }

    private func send(_ conn: NWConnection, status: String,
                      headers: [String: String], body: Data, method: String) {
        var head = "HTTP/1.1 \(status)\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        if method != "HEAD" { out.append(body) }
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}
