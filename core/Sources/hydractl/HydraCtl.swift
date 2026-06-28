import Foundation
import DownloadCore

/// CLI для ручной проверки движка:
///   hydractl <url> [--out DIR] [--connections N] [--cookie "a=b"]
///            [--header "Key: Value"]...  [--user-agent UA] [--referer URL]
@main
struct HydraCtl {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let urlString = args.first, let url = URL(string: urlString) else {
            FileHandle.standardError.write(Data("usage: hydractl <url> [--out DIR] [--connections N] [--cookie C] [--header 'K: V']\n".utf8))
            exit(2)
        }
        args.removeFirst()

        var outDir = FileManager.default.currentDirectoryPath
        var connections = 8
        var cookie: String?
        var userAgent: String?
        var referer: String?
        var extra: [String: String] = [:]

        var i = 0
        while i < args.count {
            let a = args[i]
            func next() -> String? { i += 1; return i < args.count ? args[i] : nil }
            switch a {
            case "--out": outDir = next() ?? outDir
            case "--connections": connections = Int(next() ?? "") ?? connections
            case "--cookie": cookie = next()
            case "--user-agent": userAgent = next()
            case "--referer": referer = next()
            case "--header":
                if let h = next(), let colon = h.firstIndex(of: ":") {
                    let k = String(h[..<colon]).trimmingCharacters(in: .whitespaces)
                    let v = String(h[h.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    extra[k] = v
                }
            default: break
            }
            i += 1
        }

        let session = SessionContext(cookie: cookie, userAgent: userAgent,
                                     referer: referer, extra: extra)
        let request = DownloadRequest(
            url: url,
            session: session,
            destinationDirectory: URL(fileURLWithPath: outDir, isDirectory: true),
            maxConnections: connections)

        let progress: @Sendable (DownloadProgress) -> Void = { p in
            let mb = Double(p.receivedBytes) / 1_048_576
            let speed = p.bytesPerSecond / 1_048_576
            if let frac = p.fractionCompleted {
                let pct = Int(frac * 100)
                FileHandle.standardError.write(Data(
                    String(format: "\r%3d%%  %.1f MB  %.1f MB/s  (%d conn)   ", pct, mb, speed, p.connections).utf8))
            } else {
                FileHandle.standardError.write(Data(
                    String(format: "\r%.1f MB  %.1f MB/s   ", mb, speed).utf8))
            }
        }

        do {
            let result = try await Downloader().download(request, progress: progress)
            FileHandle.standardError.write(Data("\n".utf8))
            print("Saved: \(result.path)")
        } catch {
            FileHandle.standardError.write(Data("\nError: \(error)\n".utf8))
            exit(1)
        }
    }
}
