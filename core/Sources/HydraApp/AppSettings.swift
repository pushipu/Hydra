import Foundation
import AppKit
import ServiceManagement
import DownloadCore

enum CompletionAction: String, CaseIterable, Identifiable {
    case openFolder, sound, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .openFolder: return L("Открыть папку")
        case .sound:      return L("Звук")
        case .none:       return L("Ничего")
        }
    }
}

/// Наблюдаемая модель настроек приложения. Хранит в UserDefaults, применяет
/// побочные эффекты (лимит скорости, автозапуск, очередь) и пишет подмножество
/// перехвата в общий settings.json для расширения.
@MainActor final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard
    private weak var queue: DownloadQueue?

    @Published var maxConcurrent: Int      { didSet { d.set(maxConcurrent, forKey: "maxConcurrent"); queue?.maxConcurrent = maxConcurrent } }
    @Published var threadsPerFile: Int     { didSet { d.set(threadsPerFile, forKey: "threadsPerFile"); queue?.defaultConnections = threadsPerFile; persistShared() } }
    @Published var speedLimitEnabled: Bool { didSet { d.set(speedLimitEnabled, forKey: "speedLimitEnabled"); applyRate() } }
    @Published var speedLimitMBps: Double  { didSet { d.set(speedLimitMBps, forKey: "speedLimitMBps"); applyRate() } }
    @Published var completionAction: CompletionAction { didSet { d.set(completionAction.rawValue, forKey: "completionAction") } }
    @Published var launchAtLogin: Bool     { didSet { d.set(launchAtLogin, forKey: "launchAtLogin"); applyLaunchAtLogin() } }
    @Published var quietMode: Bool         { didSet { d.set(quietMode, forKey: "quietMode") } }
    @Published var autoIntercept: Bool     { didSet { d.set(autoIntercept, forKey: "autoIntercept"); persistShared() } }
    @Published var minSizeMB: Int          { didSet { d.set(minSizeMB, forKey: "minSizeMB"); persistShared() } }
    @Published var fileTypesText: String   { didSet { d.set(fileTypesText, forKey: "fileTypesText"); persistShared() } }
    @Published var defaultDestPath: String { didSet { d.set(defaultDestPath, forKey: "defaultDestPath") } }
    @Published var dropWindowVisible: Bool { didSet { d.set(dropWindowVisible, forKey: "dropWindowVisible") } }
    /// Закреплён ли попап (не закрывать по клику снаружи).
    @Published var popoverPinned: Bool     { didSet { d.set(popoverPinned, forKey: "popoverPinned") } }

    private init() {
        // didSet не срабатывает в init — грузим напрямую, эффекты применим ниже.
        maxConcurrent    = (d.object(forKey: "maxConcurrent")    as? Int)    ?? 4
        threadsPerFile   = (d.object(forKey: "threadsPerFile")   as? Int)    ?? 8
        speedLimitEnabled = d.bool(forKey: "speedLimitEnabled")
        speedLimitMBps   = (d.object(forKey: "speedLimitMBps")   as? Double) ?? 5
        completionAction = CompletionAction(rawValue: d.string(forKey: "completionAction") ?? "") ?? .openFolder
        launchAtLogin    = d.bool(forKey: "launchAtLogin")
        quietMode        = d.bool(forKey: "quietMode")
        autoIntercept    = (d.object(forKey: "autoIntercept")    as? Bool)   ?? true
        minSizeMB        = (d.object(forKey: "minSizeMB")        as? Int)    ?? 25
        fileTypesText    = d.string(forKey: "fileTypesText") ?? "dmg, zip, iso, mp4, mkv, pkg, tar, gz, 7z"
        defaultDestPath  = d.string(forKey: "defaultDestPath")
            ?? (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory() + "/Downloads")
        dropWindowVisible = d.bool(forKey: "dropWindowVisible")
        popoverPinned     = d.bool(forKey: "popoverPinned")

        applyRate()
        persistShared()
    }

    func bind(to queue: DownloadQueue) {
        self.queue = queue
        queue.maxConcurrent = maxConcurrent
        queue.defaultConnections = threadsPerFile
    }

    func applyInterceptSettings(autoIntercept: Bool?, minSizeMB: Int?, threadsPerFile: Int?) {
        if let autoIntercept { self.autoIntercept = autoIntercept }
        if let minSizeMB { self.minSizeMB = max(0, minSizeMB) }
        if let threadsPerFile { self.threadsPerFile = min(32, max(1, threadsPerFile)) }
    }

    var defaultDestURL: URL { URL(fileURLWithPath: defaultDestPath, isDirectory: true) }

    private func applyRate() {
        RateLimiter.shared.setLimit(bytesPerSecond: speedLimitEnabled ? speedLimitMBps * 1_048_576 : 0)
    }

    private func parsedTypes() -> [String] {
        fileTypesText.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ", ·\n"))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
            .filter { !$0.isEmpty }
    }

    private func persistShared() {
        SharedSettings.save(InterceptSettings(
            autoIntercept: autoIntercept,
            minSizeBytes: Int64(minSizeMB) * 1_048_576,
            fileTypes: parsedTypes(),
            threadsPerFile: threadsPerFile,
            contextMenu: true))
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Hydra: автозапуск не применён: \(error)")
        }
    }
}
