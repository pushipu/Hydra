import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DownloadCore

/// Плавающее окно-приёмник «круг-ловушка» (макет, экран 11): перетащи сюда ссылку —
/// она уйдёт в очередь. Пульсирующее кольцо + орбитальные точки, увеличение при наведении.
struct DropTargetView: View {
    let queue: DownloadQueue
    var onClose: () -> Void
    @State private var over = false
    @State private var hover = false
    @State private var clipURL: String?    // ссылка, найденная в буфере при наведении

    private let ring: CGFloat = 105          // диаметр пунктирного кольца (−30%)
    private let dots = 6

    var body: some View {
        trap
            .frame(width: 150, height: 150)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { if hover || over { label } }
            .overlay(alignment: .topTrailing) { closeButton }
            .onHover { h in hover = h; clipURL = h ? Self.clipboardLink() : nil }
            .onTapGesture { if let u = clipURL { add(u); clipURL = nil } }
            .onDrop(of: [.url, .text, .plainText], isTargeted: $over) { handleDrop($0) }
            .animation(.easeOut(duration: 0.15), value: hover || over)
    }

    /// Всплывающая подпись при наведении/перетаскивании — поверх нижней части круга.
    @ViewBuilder private var label: some View {
        let pill = VStack(spacing: 1) {
            if let link = clipURL, !over {
                Text(L("Скачать из буфера")).font(.system(size: 11.5, weight: .semibold))
                Text(Self.linkName(link)).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            } else {
                Text(over ? L("Отпустите") : L("Бросьте ссылку")).font(.system(size: 11.5, weight: .semibold))
                Text(over ? L("добавим в Hydra") : L("или адрес из браузера")).font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
        }
        pill
            .multilineTextAlignment(.center)
            .frame(maxWidth: 150)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(clipURL != nil && !over ? Color.accent.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 0.5))
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
    }

    private var trap: some View {
        ZStack {
            // Матовая подложка-круг со сплошной внешней обводкой — однородная заливка.
            Circle().fill(.regularMaterial).frame(width: ring, height: ring)
                .overlay(Circle().strokeBorder(Color.accent.opacity(0.6), lineWidth: 2))
            // Пунктирное кольцо внутри (статичное)
            Circle()
                .strokeBorder(Color.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                .frame(width: ring - 24, height: ring - 24)
            // Орбитальные точки — на пунктирном кольце, не на внешней обводке
            ForEach(0..<dots, id: \.self) { i in OrbitDot(index: i, count: dots, radius: (ring - 24) / 2) }
            // Центр со стрелкой
            ZStack {
                Circle().fill(Color.accent.opacity(0.22)).frame(width: 59, height: 59)
                    .overlay(Circle().strokeBorder(Color.accent.opacity(0.55), lineWidth: 1))
                Image(systemName: "arrow.down").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.accent)
            }
        }
        .frame(width: ring + 36, height: ring + 36)
        .scaleEffect(over ? 1.08 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: over)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(hover && !over ? 0.5 : 0).padding(6)
    }

    // MARK: - Приём ссылок (без изменений)

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for p in providers {
            if p.canLoadObject(ofClass: NSURL.self) {
                accepted = true
                p.loadObject(ofClass: NSURL.self) { obj, _ in
                    if let u = obj as? URL { add(u.absoluteString) }
                }
            } else if p.canLoadObject(ofClass: NSString.self) {
                accepted = true
                p.loadObject(ofClass: NSString.self) { obj, _ in
                    if let s = obj as? String { Self.extractLinks(s).forEach(add) }
                }
            }
        }
        return accepted
    }

    private func add(_ s: String) {
        guard s.hasPrefix("http") else { return }   // только веб-ссылки
        Task { @MainActor in queue.addURL(s) }
    }

    static func extractLinks(_ s: String) -> [String] {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return d.matches(in: s, range: NSRange(s.startIndex..., in: s))
            .compactMap { $0.url?.absoluteString }
            .filter { $0.hasPrefix("http") }
    }

    /// http(s)-ссылка из буфера обмена (URL-тип или первая ссылка в тексте), иначе nil.
    static func clipboardLink() -> String? {
        let pb = NSPasteboard.general
        if let url = NSURL(from: pb) as URL?, url.scheme?.hasPrefix("http") == true { return url.absoluteString }
        if let s = pb.string(forType: .string) { return extractLinks(s).first }
        return nil
    }

    /// Короткое имя для подписи: имя файла из URL, иначе хост.
    static func linkName(_ s: String) -> String {
        guard let u = URL(string: s) else { return s }
        let name = u.lastPathComponent
        return name.isEmpty || name == "/" ? (u.host ?? s) : name
    }
}

/// Точка на орбите кольца: мигает (opacity/scale) со сдвигом фазы по индексу.
private struct OrbitDot: View {
    let index: Int
    let count: Int
    let radius: CGFloat
    @State private var on = false

    var body: some View {
        let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2
        Circle().fill(Color.accent).frame(width: 5, height: 5)
            .scaleEffect(on ? 1 : 0.6)
            .opacity(on ? 1 : 0.22)
            .offset(x: radius * CGFloat(cos(angle)), y: radius * CGFloat(sin(angle)))
            .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true).delay(Double(index) * 0.22), value: on)
            .onAppear { on = true }
    }
}
