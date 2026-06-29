import SwiftUI
import AppKit
import DownloadCore

private enum Filter: Hashable { case all, active, queued, done, failed, source(String) }
private enum SortKey: String, CaseIterable, Identifiable { case added, name, size; var id: String { rawValue }
    var label: String { L(self == .added ? "По добавлению" : self == .name ? "По имени" : "По размеру") } }

struct MainWindow: View {
    @ObservedObject var queue: DownloadQueue
    @ObservedObject private var loc = Localizer.shared
    var onOpenSettings: () -> Void = {}
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var selection = Set<Int>()
    @State private var sort: SortKey = .added

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            VStack(spacing: 0) {
                table
                footer
            }
            .navigationTitle(L("Загрузки"))
            .searchable(text: $search, placement: .toolbar, prompt: L("Поиск"))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $filter) {
                        Text(L("Все")).tag(Filter.all)
                        Text(L("Активные")).tag(Filter.active)
                        Text(L("Готовые")).tag(Filter.done)
                    }.pickerStyle(.segmented).frame(width: 240)
                }
                ToolbarItem {
                    Menu {
                        Picker(L("Сортировка"), selection: $sort) {
                            ForEach(SortKey.allCases) { Text($0.label).tag($0) }
                        }
                    } label: { Label(L("Сортировка"), systemImage: "arrow.up.arrow.down") }
                }
                ToolbarItem {
                    Button { onOpenSettings() } label: { Label(L("Настройки"), systemImage: "gearshape") }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    // MARK: Сайдбар

    private var sidebar: some View {
        List(selection: $filter) {
            Section(L("Библиотека")) {
                sideRow(.all, L("Все"), queue.tasks.count, .accent)
                sideRow(.active, L("Активные"), queue.active, .accent)
                sideRow(.queued, L("В очереди"), queue.queuedCount, .secondary)
                sideRow(.done, L("Завершённые"), queue.finishedCount, Color(nsColor: .systemGreen))
                sideRow(.failed, L("Ошибки"), queue.failedCount, Color(nsColor: .systemRed))
            }
            if !sources.isEmpty {
                Section(L("Источники")) {
                    ForEach(sources, id: \.self) { h in
                        Label { Text(h).lineLimit(1) } icon: {
                            Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.tag(Filter.source(h))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sideRow(_ f: Filter, _ title: String, _ count: Int, _ tone: Color) -> some View {
        HStack(spacing: 9) {
            Circle().fill(tone).frame(width: 7, height: 7)
            Text(title)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
        }.tag(f)
    }

    private var sources: [String] {
        Array(Set(queue.tasks.compactMap { $0.url.host })).sorted()
    }

    // MARK: Таблица

    private var table: some View {
        Table(filtered, selection: $selection) {
            TableColumn(L("Имя")) { t in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06)).frame(width: 26, height: 26)
                        .overlay(Text(fileBadge(t.filename)).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.filename).lineLimit(1).truncationMode(.middle)
                        Text(host(t.url)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            TableColumn(L("Статус")) { t in
                let s = statusInfo(t)
                HStack(spacing: 7) {
                    Circle().fill(s.tone).frame(width: 7, height: 7)
                    Text(s.text).foregroundStyle(.secondary).lineLimit(1)
                }
            }.width(170)
            TableColumn(L("Размер")) { t in
                Text(taskSizeText(t)).foregroundStyle(.secondary).monospacedDigit()
            }.width(90)
            TableColumn(L("Источник")) { t in
                HStack(spacing: 6) {
                    Image(systemName: t.source.icon).font(.system(size: 10)).foregroundStyle(.tertiary)
                    Text(t.source.label).foregroundStyle(.secondary).lineLimit(1)
                }
            }.width(150)
        }
        .contextMenu(forSelectionType: Int.self) { ids in rowMenu(ids) }
        .onDeleteCommand { deleteSelected() }
    }

    @ViewBuilder private func rowMenu(_ ids: Set<Int>) -> some View {
        let targets = ids.isEmpty ? selection : ids
        if targets.count == 1, let t = queue.tasks.first(where: { $0.id == targets.first }) {
            switch t.state {
            case .running: Button(L("Пауза")) { queue.pause(t.id) }
            case .paused, .queued: Button(L("Возобновить")) { queue.resume(t.id) }
            case .done: Button(L("Показать в Finder")) { reveal(t) }
            case .failed, .cancelled: Button(L("Повторить")) { queue.retry(t.id) }
            }
            if t.state == .done || t.state == .failed || t.state == .cancelled {
                Button(L("Скачать заново")) { queue.redownload(t.id) }
            }
        }
        Button(L("Копировать ссылку")) { copyLinks(targets) }
        Button(L("Удалить"), role: .destructive) { for id in targets { queue.remove(id, deleteFile: !isDone(id)) } }
    }

    // MARK: Подвал

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(queue.tasks.count) \(L("загрузок")) · \(queue.active) \(L("активна"))")
            if queue.totalSpeed > 0 {
                Text("· \(fmtSpeed(queue.totalSpeed))").fontWeight(.semibold)
            }
            Spacer()
            if queue.hasHistory {
                Button(L("Очистить историю")) { queue.clearHistory() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Text("⌫ — \(L("удалить"))").foregroundStyle(.tertiary)
        }
        .font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: Логика

    private var filtered: [DownloadTask] {
        var ts = queue.tasks
        switch filter {
        case .all: break
        case .active: ts = ts.filter { $0.state == .running }
        case .queued: ts = ts.filter { $0.state == .queued }
        case .done: ts = ts.filter { $0.state == .done }
        case .failed: ts = ts.filter { $0.state == .failed || $0.state == .cancelled }
        case .source(let h): ts = ts.filter { $0.url.host == h }
        }
        if !search.isEmpty { ts = ts.filter { $0.filename.localizedCaseInsensitiveContains(search) } }
        switch sort {
        case .added: break
        case .name: ts.sort { $0.filename.localizedCompare($1.filename) == .orderedAscending }
        case .size: ts.sort { ($0.progress?.totalBytes ?? 0) > ($1.progress?.totalBytes ?? 0) }
        }
        return ts
    }

    private func isDone(_ id: Int) -> Bool { queue.tasks.first { $0.id == id }?.state == .done }

    private func copyLinks(_ ids: Set<Int>) {
        let urls = queue.tasks.filter { ids.contains($0.id) }.map { $0.url.absoluteString }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.joined(separator: "\n"), forType: .string)
    }
    private func deleteSelected() { for id in selection { queue.remove(id, deleteFile: !isDone(id)) }; selection = [] }
    private func reveal(_ t: DownloadTask) { if let p = t.path { revealInFinder(p) } }
}
