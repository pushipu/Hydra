import Foundation

/// Заголовки/куки текущей браузерной сессии, которые нужно повторить в каждом
/// из параллельных запросов, чтобы авторизованная ссылка скачалась корректно.
public struct SessionContext: Sendable, Equatable {
    /// Произвольные HTTP-заголовки (Cookie, User-Agent, Referer, Authorization, …).
    public var headers: [String: String]

    public init(headers: [String: String] = [:]) {
        self.headers = headers
    }

    /// Удобный конструктор из типовых полей, которые отдаёт расширение.
    public init(cookie: String? = nil,
                userAgent: String? = nil,
                referer: String? = nil,
                extra: [String: String] = [:]) {
        var h = extra
        if let cookie, !cookie.isEmpty { h["Cookie"] = cookie }
        if let userAgent, !userAgent.isEmpty { h["User-Agent"] = userAgent }
        if let referer, !referer.isEmpty { h["Referer"] = referer }
        self.headers = h
    }

    /// Накатывает заголовки сессии на запрос. `Range`/`Accept-Encoding`,
    /// проставленные движком, не перетираются. URLSession игнорирует системные заголовки.
    public func apply(to request: inout URLRequest) {
        for (key, value) in headers {
            let lower = key.lowercased()
            guard lower != "range", lower != "accept-encoding" else { continue }
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}
