import Foundation

/// Покомпонентное сравнение версий вида `a.b.c` (ведущая `v` игнорируется).
/// `true`, если `a` строго новее `b`. Недостающие компоненты считаются нулём.
public func isVersion(_ a: String, newerThan b: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        (s.hasPrefix("v") ? String(s.dropFirst()) : s).split(separator: ".").map { Int($0) ?? 0 }
    }
    let pa = parts(a), pb = parts(b)
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0
        let y = i < pb.count ? pb[i] : 0
        if x != y { return x > y }
    }
    return false
}
