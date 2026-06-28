import Foundation

/// Глобальный лимит скорости загрузки — token bucket. Все потоки всех загрузок
/// перед учётом байт зовут `throttle`, который спит ровно столько, чтобы суммарно
/// не превысить лимит. При лимите 0 — no-op (без ограничения).
public final class RateLimiter: @unchecked Sendable {
    public static let shared = RateLimiter()
    public init() {}

    private let lock = NSLock()
    private var bytesPerSec: Double = 0      // 0 = без ограничения
    private var allowance: Double = 0
    private var last = Date()

    public func setLimit(bytesPerSecond: Double) {
        lock.lock()
        bytesPerSec = max(0, bytesPerSecond)
        allowance = bytesPerSec
        last = Date()
        lock.unlock()
    }

    /// Блокирует вызывающий поток, пока бюджет не позволит `n` байт.
    /// Зовётся из delegate-очереди URLSession (concurrent) — сон одного потока
    /// не стопорит остальные, общий bucket держит суммарный лимит.
    public func throttle(_ n: Int) {
        lock.lock()
        let rate = bytesPerSec
        guard rate > 0 else { lock.unlock(); return }
        let now = Date()
        allowance += now.timeIntervalSince(last) * rate
        last = now
        if allowance > rate { allowance = rate }      // bucket не больше 1 секунды
        allowance -= Double(n)
        let deficitSec = allowance < 0 ? -allowance / rate : 0
        lock.unlock()
        if deficitSec > 0 { Thread.sleep(forTimeInterval: min(deficitSec, 1.0)) }
    }
}
