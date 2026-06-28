import SwiftUI
import AppKit
import DownloadCore

struct SettingsView: View {
    @ObservedObject var queue: DownloadQueue
    @ObservedObject private var s = AppSettings.shared
    @ObservedObject private var loc = Localizer.shared
    @State private var pane: Pane? = .parallelism

    /// Разделы настроек — сайдбар как в System Settings (по макету, экран 06).
    enum Pane: String, CaseIterable, Identifiable {
        case parallelism, intercept, completion, folders, system
        var id: String { rawValue }
        var title: String {
            switch self {
            case .parallelism: return "Загрузка"
            case .intercept:   return "Перехват"
            case .completion:  return "Завершение"
            case .folders:     return "Папки"
            case .system:      return "Система"
            }
        }
        var icon: String {
            switch self {
            case .parallelism: return "arrow.down.circle"
            case .intercept:   return "link"
            case .completion:  return "checkmark.circle"
            case .folders:     return "folder"
            case .system:      return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(L(p.title), systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(206)
        } detail: {
            detail(for: pane ?? .parallelism)
                .navigationTitle(L((pane ?? .parallelism).title))
        }
        .frame(width: 680, height: 460)
    }

    @ViewBuilder
    private func detail(for pane: Pane) -> some View {
        switch pane {
        case .parallelism: parallelism
        case .intercept:   intercept
        case .completion:  completion
        case .folders:     folders
        case .system:      system
        }
    }

    private var parallelism: some View {
        Form {
            Section(L("Одновременные загрузки")) {
                stepperRow(L("Качать одновременно"), value: $s.maxConcurrent, in: 1...8)
                stepperRow(L("Потоков на файл"), value: $s.threadsPerFile, in: 1...16)
            }
            Section(L("Скорость")) {
                Toggle(L("Ограничивать скорость"), isOn: $s.speedLimitEnabled)
                if s.speedLimitEnabled {
                    HStack {
                        Slider(value: $s.speedLimitMBps, in: 0.5...100, step: 0.5)
                        Text("\(s.speedLimitMBps, specifier: "%.1f") \(L("МБ"))/\(L("с"))")
                            .monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var intercept: some View {
        Form {
            Section(L("Перехват из браузера")) {
                Toggle(L("Перехватывать автоматически"), isOn: $s.autoIntercept)
                stepperRow(L("Минимальный размер файла"), suffix: " \(L("МБ"))", value: $s.minSizeMB, in: 0...4096, step: 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Типы файлов"))
                    TextField("dmg, zip, iso, mp4…", text: $s.fileTypesText)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Section {
                Text(L("Эти настройки применяются и в браузерном расширении — оно читает их из приложения."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var completion: some View {
        Form {
            Section(L("По завершении")) {
                Picker(L("Действие"), selection: $s.completionAction) {
                    ForEach(CompletionAction.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(L("Тихий режим (без уведомлений, кроме ошибок)"), isOn: $s.quietMode)
            }
        }
        .formStyle(.grouped)
    }

    private var system: some View {
        Form {
            Section(L("Общие")) {
                Picker(L("Язык"), selection: $loc.lang) {
                    ForEach(Lang.allCases) { Text($0.nativeName).tag($0) }
                }
                Toggle(L("Запуск при входе в систему"), isOn: $s.launchAtLogin)
                Toggle(L("Плавающее окно для перетаскивания ссылок"), isOn: $s.dropWindowVisible)
            }
        }
        .formStyle(.grouped)
    }

    private var folders: some View {
        Form {
            Section(L("Папка загрузок по умолчанию")) {
                HStack {
                    Text(s.defaultDestPath).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Выбрать…"), action: chooseFolder)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Ряд формы: подпись со значением слева, степпер справа — выровнены по центру.
    private func stepperRow(_ title: String, suffix: String = "", value: Binding<Int>,
                            in range: ClosedRange<Int>, step: Int = 1) -> some View {
        HStack {
            Text("\(title): \(value.wrappedValue)\(suffix)")
            Spacer()
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.directoryURL = s.defaultDestURL
        if p.runModal() == .OK, let url = p.url { s.defaultDestPath = url.path }
    }
}
