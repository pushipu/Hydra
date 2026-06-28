import SwiftUI
import DownloadCore

extension Color {
    /// Системный акцент пользователя (дизайн: берётся из AccentColor).
    static let accent = Color(nsColor: .controlAccentColor)
}

// Форматтеры и хелперы, общие для поповера и большого окна.

func fmtBytes(_ b: Double) -> String {
    let keys = ["Б", "КБ", "МБ", "ГБ", "ТБ"]
    var v = b, i = 0
    while v >= 1024 && i < keys.count - 1 { v /= 1024; i += 1 }
    let unit = L(keys[i])
    return i == 0 ? "\(Int(v)) \(unit)" : String(format: "%.1f %@", v, unit)
}

func fmtSpeed(_ bps: Double) -> String { "\(fmtBytes(bps))/\(L("с"))" }

func fmtETA(_ secs: Double) -> String {
    guard secs.isFinite, secs >= 0, secs < 360_000 else { return "—" }
    let s = Int(secs)
    if s >= 3600 { return "\(s / 3600) \(L("ч")) \((s % 3600) / 60) \(L("мин"))" }
    if s >= 60 { return "\(s / 60) \(L("мин")) \(s % 60) \(L("с"))" }
    return "\(s) \(L("с"))"
}

/// Тип-бейдж файла из расширения (DMG / ZIP / …).
func fileBadge(_ name: String) -> String {
    let ext = (name as NSString).pathExtension.uppercased()
    return ext.isEmpty ? "FILE" : String(ext.prefix(4))
}

func host(_ url: URL) -> String { url.host ?? url.absoluteString }

/// Текст статуса + цвет-тон для строки (общий для окна и поповера).
func statusInfo(_ t: DownloadTask) -> (text: String, tone: Color) {
    func pct(_ p: DownloadProgress?) -> String { p?.fractionCompleted.map { " · \(Int($0 * 100))%" } ?? "" }
    switch t.state {
    case .running:   return ("\(L("Скачивается"))\(pct(t.progress))", .accent)
    case .queued:    return (L("В очереди"), .secondary)
    case .paused:    return ("\(L("Пауза"))\(pct(t.progress))", .secondary)
    case .done:      return (L("Завершено"), Color(nsColor: .systemGreen))
    case .failed:    return (t.error ?? L("Ошибка"), Color(nsColor: .systemRed))
    case .cancelled: return (L("Отменено"), .secondary)
    }
}

func taskSizeText(_ t: DownloadTask) -> String {
    if let total = t.progress?.totalBytes { return fmtBytes(Double(total)) }
    if let path = t.path,
       let attrs = try? FileManager.default.attributesOfItem(atPath: path),
       let sz = attrs[.size] as? Int64 {
        return fmtBytes(Double(sz))
    }
    return "—"
}
