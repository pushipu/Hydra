import SwiftUI
import AppKit
import DownloadCore

struct ContentView: View {
    @ObservedObject var queue: DownloadQueue
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var loc = Localizer.shared   // перерисовка при смене языка
    /// Действия пробрасывает StatusBarController (попап вне SwiftUI-сцен).
    var onOpenWindow: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    @State private var addingURL = false
    @State private var urlText = ""
    @State private var selected: Int?    // открыта детальная карточка загрузки (экран 05)

    /// Поповер показывает только живые загрузки, без строк истории (история — в окне).
    private var liveTasks: [DownloadTask] { queue.tasks.filter { !$0.fromHistory } }

    var body: some View {
        Group {
            if let id = selected, let task = queue.tasks.first(where: { $0.id == id }) {
                DownloadDetail(task: task, queue: queue, maxHeight: maxPopoverHeight) {
                    withAnimation(.easeOut(duration: 0.18)) { selected = nil }
                }
            } else {
                mainList.frame(height: 432)
            }
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .tint(.accent)
    }

    /// Попап адаптивный, но не выше 70% экрана.
    private var maxPopoverHeight: CGFloat { (NSScreen.main?.visibleFrame.height ?? 900) * 0.7 }

    private var mainList: some View {
        VStack(spacing: 0) {
            header
            if !liveTasks.isEmpty { summaryRow }
            if addingURL { addBar }
            Divider().opacity(0.6)

            if liveTasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(liveTasks) { task in
                            DownloadRow(task: task, queue: queue) {
                                withAnimation(.easeOut(duration: 0.18)) { selected = task.id }
                            }
                            Divider().opacity(0.5).padding(.leading, 13)
                        }
                    }
                }
                footer
            }
        }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 7) {
            AppMark(size: 16)
            Text("Hydra").font(.system(size: 13, weight: .semibold))
            Spacer()
            if queue.active > 0 {
                HStack(spacing: 6) {
                    Circle().fill(Color.accent).frame(width: 6, height: 6)
                    Text(fmtSpeed(queue.totalSpeed))
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.trailing, 2)
            }
            HeaderIcon(symbol: settings.popoverPinned ? "pin.fill" : "pin",
                       help: L("Закрепить попап"),
                       tint: settings.popoverPinned ? .accent : .secondary) {
                settings.popoverPinned.toggle()
            }
            HeaderIcon(symbol: settings.dropWindowVisible ? "arrow.down.app.fill" : "arrow.down.app",
                       help: L("Окно перетаскивания ссылок"),
                       tint: settings.dropWindowVisible ? .accent : .secondary) {
                settings.dropWindowVisible.toggle()
            }
            HeaderIcon(symbol: "macwindow", help: L("Все загрузки")) { onOpenWindow() }
            HeaderIcon(symbol: "gearshape", help: L("Настройки")) { onOpenSettings() }
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
    }

    private var summaryRow: some View {
        HStack(spacing: 6) {
            (Text("\(queue.active)").font(.system(size: 12, weight: .semibold)).foregroundColor(.primary)
             + Text(" " + L(queue.active == 1 ? "активна" : "активны")).font(.system(size: 12)).foregroundColor(.secondary))
            if queue.queuedCount > 0 {
                Text("·").foregroundStyle(.tertiary)
                Text("\(queue.queuedCount) \(L("в очереди"))").foregroundStyle(.secondary)
            }
            Spacer()
            if queue.finishedCount > 0 {
                Text("\(queue.finishedCount) \(L("завершено"))").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12)).monospacedDigit()
        .padding(.horizontal, 13).padding(.bottom, 8)
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(L("Вставить ссылку…"), text: $urlText)
                .textFieldStyle(.plain).font(.system(size: 12.5)).onSubmit(submitURL)
            if !urlText.isEmpty {
                Button(L("Скачать"), action: submitURL)
                    .buttonStyle(PressableStyle()).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accent)
            }
        }
        .padding(.horizontal, 13).padding(.bottom, 9)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func submitURL() {
        queue.addURL(urlText); urlText = ""
        withAnimation(.easeOut(duration: 0.18)) { addingURL = false }
    }

    // MARK: Пусто (экран 02 «Первый запуск»)

    private var emptyState: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accent.opacity(0.14)).frame(width: 46, height: 46)
                .overlay(Image(systemName: "arrow.down").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.accent))
            Text(L("Здесь появятся загрузки"))
                .font(.system(size: 15, weight: .semibold)).padding(.top, 14)
            Text(L("Нажмите «Скачать через Hydra» в браузере\nили вставьте ссылку вручную"))
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(2).padding(.top, 5)
            Button {
                withAnimation(.easeOut(duration: 0.18)) { addingURL = true }
            } label: {
                HStack {
                    Text(L("Вставить ссылку…")).foregroundStyle(.tertiary)
                    Spacer()
                    Text("⌘V").foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
            }
            .buttonStyle(PressableStyle()).padding(.top, 15).frame(width: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Подвал

    private var footer: some View {
        HStack {
            if queue.active > 0 {
                Button(L("Пауза всех")) { queue.pauseAll() }.buttonStyle(PressableStyle())
            } else if queue.pausedCount > 0 {
                Button(L("Возобновить всё")) { queue.resumeAll() }.buttonStyle(PressableStyle())
            }
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.18)) { addingURL.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text(L("Добавить")).font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.accent))
            }
            .buttonStyle(PressableStyle())
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 11).padding(.vertical, 8)
        .overlay(Divider().opacity(0.6), alignment: .top)
    }
}

// MARK: - Строка загрузки

private struct DownloadRow: View {
    let task: DownloadTask
    @ObservedObject var queue: DownloadQueue
    var onOpen: () -> Void = {}
    @State private var hovering = false

    private var isRich: Bool { (task.state == .running || task.state == .paused) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                badge
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.filename).font(.system(size: 13, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(subtitleColor)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                trailing
            }

            if isRich, let p = task.progress {
                HStack {
                    Text("\(fmtBytes(Double(p.receivedBytes)))\(p.totalBytes.map { " \(L("из")) \(fmtBytes(Double($0)))" } ?? "")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let f = p.fractionCompleted {
                        Text("\(Int(f * 100))%").foregroundStyle(.primary).fontWeight(.medium)
                    }
                }
                .font(.system(size: 12)).monospacedDigit()

                if let blocks = p.blocks, !blocks.isEmpty {
                    BlockGrid(blocks: blocks, dimmed: task.state == .paused)
                    HStack {
                        Text("\(blocks.filter { $0 == .done }.count) / \(blocks.count) \(L("блоков")) · \(p.connections) \(L("потоков"))")
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if task.state == .running, let eta = fmtRemaining(p) {
                            Text("\(L("осталось")) \(eta)").foregroundStyle(.tertiary).monospacedDigit()
                        }
                    }
                    .font(.system(size: 11))
                } else {
                    // одно-поточная: сетки блоков нет
                    ThreadBars(progress: p, dimmed: task.state == .paused)
                    HStack {
                        Text(L("Один поток")).foregroundStyle(.tertiary)
                        Spacer()
                        if task.state == .running, let eta = fmtRemaining(p) {
                            Text("\(L("осталось")) \(eta)").foregroundStyle(.tertiary).monospacedDigit()
                        }
                    }
                    .font(.system(size: 11))
                }
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
    }

    // тип-бейдж файла (DMG / ZIP / …)
    private var badge: some View {
        let active = task.state == .running
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(active ? Color.accent.opacity(0.16) : Color.primary.opacity(0.06))
            .frame(width: 30, height: 30)
            .overlay(
                Text(fileBadge(task.filename))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(active ? Color.accent : Color.secondary)
            )
    }

    private var subtitle: String {
        switch task.state {
        case .running:   return host(task.url)
        case .queued:    return "\(L("В очереди · приоритет")) \(max(1, queuePosition))"
        case .paused:    return L("Пауза")
        case .done:      return task.path.map { "\(fmtBytes(Double(fileSize($0)))) · \(L("готово"))" } ?? L("Готово")
        case .failed:    return task.error ?? L("Ошибка")
        case .cancelled: return L("Отменено")
        }
    }

    private var subtitleColor: Color {
        task.state == .failed ? Color(nsColor: .systemRed) : .secondary
    }

    private var queuePosition: Int {
        let q = queue.tasks.filter { $0.state == .queued }
        return (q.firstIndex { $0.id == task.id } ?? 0) + 1
    }

    @ViewBuilder private var trailing: some View {
        switch task.state {
        case .running:
            CircleButton(symbol: "pause.fill") { queue.pause(task.id) }
        case .paused:
            CircleButton(symbol: "play.fill") { queue.resume(task.id) }
        case .queued:
            if hovering { CircleButton(symbol: "play.fill") { queue.forceStart(task.id) } }
            else { Text("—").font(.system(size: 13)).foregroundStyle(.tertiary) }
        case .done:
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color(nsColor: .systemGreen).opacity(0.16)))
            if hovering, let p = task.path { SmallButton("Finder") { revealInFinder(p) } }
        case .failed, .cancelled:
            if hovering { SmallButton(L("Повторить")) { queue.retry(task.id) } }
        }
        if hovering && task.state != .running && task.state != .paused {
            CircleButton(symbol: "xmark") { withAnimation { queue.remove(task.id, deleteFile: task.state != .done) } }
        }
    }

    private func fileSize(_ path: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64) ?? 0
    }
}

// MARK: - Детали одной загрузки (экран 05): сегменты по потокам, скорость, сводка

private struct DownloadDetail: View {
    let task: DownloadTask
    @ObservedObject var queue: DownloadQueue
    var maxHeight: CGFloat
    var onBack: () -> Void
    @State private var spark: [Double] = []   // история скорости этой загрузки (последние тики)

    private var p: DownloadProgress? { task.progress }
    private var active: Bool { task.state == .running || task.state == .paused }
    private let chrome: CGFloat = 96           // навбар + панель действий

    /// Высота контента из данных (без GeometryReader — он внутри ScrollView даёт цикл).
    private var contentHeight: CGFloat {
        var h: CGFloat = 26 + 52               // padding + hero
        if let segs = p?.segments, !segs.isEmpty { h += 40 + CGFloat(segs.count) * 24 }
        if active { h += 290 }                  // блоки «Скорость» + «Сводка»
        return h
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider().opacity(0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    if let segs = p?.segments, !segs.isEmpty { segments(segs) }
                    if active { speedAndSummary }
                }
                .padding(13)
            }
            .frame(height: min(contentHeight, maxHeight - chrome))   // под контент, но ≤70% экрана
            actionBar
        }
        .onAppear {
            // Посев спарклайна, чтобы график был «живым» сразу (и в демо, и на старте реальной).
            // Реалистичный профиль: разгон к текущей скорости + случайный джиттер.
            if spark.isEmpty, let bps = p?.bytesPerSecond, bps > 0 {
                var v = bps * 0.25
                spark = (0..<48).map { _ in
                    v += (bps - v) * 0.16                                  // плавный разгон к bps
                    return max(bps * 0.1, v + Double.random(in: -0.13...0.13) * bps)
                }
            }
        }
        .onChange(of: p?.receivedBytes) { _ in
            guard task.state == .running, let bps = p?.bytesPerSecond else { return }
            spark.append(bps)
            if spark.count > 60 { spark.removeFirst(spark.count - 60) }
        }
    }

    private var navBar: some View {
        HStack(spacing: 7) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accent).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            Text(task.filename).font(.system(size: 13, weight: .semibold))
                .lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
    }

    // Шапка: бейдж типа + имя + источник·%
    private var hero: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accent.opacity(0.16)).frame(width: 44, height: 44)
                .overlay(Text(fileBadge(task.filename)).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.filename).font(.system(size: 14, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if let f = p?.fractionCompleted {
                Text("\(Int(f * 100))%").font(.system(size: 24, weight: .semibold)).monospacedDigit()
            }
        }
    }

    private var subtitle: String {
        var parts = [host(task.url)]
        if let total = p?.totalBytes { parts.append(fmtBytes(Double(total))) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func segments(_ segs: [SegmentInfo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("Сегменты файла по потокам"))
            VStack(spacing: 10) {
                ForEach(segs.sorted { $0.range.lowerBound < $1.range.lowerBound }) { s in
                    let len = Double(s.range.upperBound - s.range.lowerBound + 1)
                    let frac = len > 0 ? Double(s.received) / len : 0
                    HStack(spacing: 9) {
                        Text("#\(s.id)").font(.system(size: 11)).foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .leading).monospacedDigit()
                        Text("\(fmtBytes(Double(s.range.lowerBound)))–\(fmtBytes(Double(s.range.upperBound)))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading).monospacedDigit().lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.1))
                                Capsule().fill(Color.accent)
                                    .frame(width: max(2, geo.size.width * min(1, max(0, frac))))
                                    .animation(.linear(duration: 0.5), value: frac)
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int(frac * 100))%").font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing).monospacedDigit()
                    }
                }
            }
            .padding(.vertical, 11).padding(.horizontal, 12).background(card)
            .opacity(task.state == .paused ? 0.5 : 1)
        }
    }

    private var speedAndSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(L("Скорость"))
                VStack(spacing: 7) {
                    Sparkline(values: spark).frame(height: 46)
                    HStack {
                        Text(fmtSpeed(p?.bytesPerSecond ?? 0)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        Spacer()
                        if let avg = avgSpeed {
                            Text("\(L("средняя")) \(fmtSpeed(avg))").font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .padding(12).background(card)
            }
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(L("Сводка"))
                VStack(spacing: 0) {
                    statRow(L("Осталось"), etaText)
                    rowSep
                    statRow(L("Прошло"), fmtETA(max(0, Date().timeIntervalSince(task.startedAt))))
                    rowSep
                    statRow(L("Скачано"), fmtBytes(Double(p?.receivedBytes ?? 0)))
                    rowSep
                    statRow(L("Потоков"), "\(p?.connections ?? 0)")
                }
                .padding(.horizontal, 12).padding(.vertical, 4).background(card)
            }
        }
    }

    private var card: some View { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)) }
    private var rowSep: some View { Divider().opacity(0.35) }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
            .kerning(0.5)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
        }
        .padding(.vertical, 8)
    }

    private var etaText: String { p.flatMap(fmtRemaining) ?? "—" }

    private var avgSpeed: Double? {
        guard !spark.isEmpty else { return nil }
        let nz = spark.filter { $0 > 0 }
        return nz.isEmpty ? nil : nz.reduce(0, +) / Double(nz.count)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            switch task.state {
            case .running:
                detailButton(L("Приостановить"), filled: true) { queue.pause(task.id) }
                detailButton(L("Отмена")) { queue.remove(task.id, deleteFile: true); onBack() }
            case .paused:
                detailButton(L("Возобновить"), filled: true) { queue.resume(task.id) }
                detailButton(L("Отмена")) { queue.remove(task.id, deleteFile: true); onBack() }
            case .done:
                detailButton(L("Показать в Finder"), filled: true) { if let p = task.path { revealInFinder(p) } }
            case .failed, .cancelled:
                detailButton(L("Повторить"), filled: true) { queue.retry(task.id) }
                detailButton(L("Удалить")) { queue.remove(task.id, deleteFile: true); onBack() }
            case .queued:
                detailButton(L("Возобновить"), filled: true) { queue.forceStart(task.id) }
                detailButton(L("Отмена")) { queue.remove(task.id, deleteFile: true); onBack() }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .overlay(Divider().opacity(0.6), alignment: .top)
    }

    private func detailButton(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(filled ? .white : .secondary)
                .frame(maxWidth: filled ? .infinity : nil)
                .padding(.horizontal, filled ? 8 : 14).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(filled ? Color.accent : Color.primary.opacity(0.06)))
        }
        .buttonStyle(PressableStyle())
    }
}

// Спарклайн скорости (линия + лёгкая заливка). Пусто → ровная базовая линия.
private struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let maxV = max(values.max() ?? 1, 1)
            let n = max(values.count - 1, 1)
            let pts: [CGPoint] = values.enumerated().map { i, v in
                CGPoint(x: w * CGFloat(i) / CGFloat(n), y: h - h * CGFloat(v / maxV))
            }
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: h)); pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: h)); p.closeSubpath()
                    }.fill(Color.accent.opacity(0.16))
                    Path { p in p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) } }
                        .stroke(Color.accent, style: .init(lineWidth: 1.6, lineJoin: .round))
                } else {
                    Path { p in p.move(to: CGPoint(x: 0, y: h - 1)); p.addLine(to: CGPoint(x: w, y: h - 1)) }
                        .stroke(Color.accent.opacity(0.3), lineWidth: 1.5)
                }
            }
        }
    }
}

// MARK: - Сетка блоков файла («дефраг»): видно все блоки и сколько из них качается

private struct BlockGrid: View {
    let blocks: [BlockState]
    let dimmed: Bool
    private let cell: CGFloat = 7
    private let gap: CGFloat = 2

    var body: some View {
        let cols = [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: gap)]
        LazyVGrid(columns: cols, spacing: gap) {
            ForEach(blocks.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color(blocks[i])).frame(width: cell, height: cell)
            }
        }
        .opacity(dimmed ? 0.5 : 1)
        .animation(.easeOut(duration: 0.25), value: blocks)
    }

    private func color(_ s: BlockState) -> Color {
        switch s {
        case .done:   return .accent                       // готов
        case .active: return Color.accent.opacity(0.42)    // качается сейчас
        case .empty:  return Color.primary.opacity(0.09)   // ещё не начат
        }
    }
}

// MARK: - Потоковые бары (по сегментам)

private struct ThreadBars: View {
    let progress: DownloadProgress
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 3) {
            let segs = progress.segments ?? []
            if segs.isEmpty {
                // нет live-сегментов — общий бар
                bar(progress.fractionCompleted ?? 0)
            } else {
                ForEach(segs) { s in
                    let len = Double(s.range.upperBound - s.range.lowerBound + 1)
                    bar(len > 0 ? Double(s.received) / len : 0)
                }
            }
        }
        .frame(height: 5)
        .opacity(dimmed ? 0.5 : 1)
    }

    private func bar(_ frac: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule().fill(Color.accent)
                    .frame(width: max(2, geo.size.width * min(1, max(0, frac))))
                    .animation(.linear(duration: 0.5), value: frac)
            }
        }
    }
}

// MARK: - Кнопки

private struct CircleButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct SmallButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.14), lineWidth: 0.5))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct HeaderIcon: View {
    let symbol: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(tint)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle()).help(help)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Строка меню: стрелка скачивания (как иконка приложения), монохром под тему

/// Стрелка скачивания в строке меню (template → адаптируется под светлую/тёмную тему).
/// Тот же мотив, что в иконке приложения: стержень + наконечник + линия-«поднос».
func hydraArrowGlyph() -> NSImage {
    let w: CGFloat = 13, h: CGFloat = 15
    let img = NSImage(size: CGSize(width: w, height: h))
    img.lockFocus()
    NSColor.black.setFill()
    let cx = w / 2
    // линия-поднос снизу
    NSBezierPath(roundedRect: NSRect(x: 1.3, y: 0.4, width: w - 2.6, height: 1.9), xRadius: 0.95, yRadius: 0.95).fill()
    // стержень
    NSBezierPath(roundedRect: NSRect(x: cx - 1.1, y: 6.6, width: 2.2, height: 7.2), xRadius: 1.1, yRadius: 1.1).fill()
    // наконечник вниз
    let head = NSBezierPath()
    head.move(to: NSPoint(x: cx - 4.2, y: 7.4))
    head.line(to: NSPoint(x: cx + 4.2, y: 7.4))
    head.line(to: NSPoint(x: cx, y: 3.0))
    head.close(); head.fill()
    img.unlockFocus(); img.isTemplate = true
    return img
}

func hydraPauseGlyph() -> NSImage {
    let s: CGFloat = 13
    let img = NSImage(size: CGSize(width: s, height: s))
    img.lockFocus()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(x: s/2 - 3.6, y: 2, width: 2.7, height: s - 4), xRadius: 1.2, yRadius: 1.2).fill()
    NSBezierPath(roundedRect: NSRect(x: s/2 + 0.9, y: 2, width: 2.7, height: s - 4), xRadius: 1.2, yRadius: 1.2).fill()
    img.unlockFocus(); img.isTemplate = true
    return img
}

/// Единый знак Hydra: акцентная плитка со стрелкой (как иконка приложения).
struct AppMark: View {
    var size: CGFloat = 15
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Color.accent)
            .frame(width: size, height: size)
            .overlay(Image(systemName: "arrow.down").font(.system(size: size * 0.62, weight: .bold)).foregroundStyle(.white))
    }
}

