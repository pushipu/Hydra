import SwiftUI
import AppKit

/// Простой онбординг первого запуска (макет, экран 07): приветствие, разрешения
/// и установка расширения с живой проверкой связки.
struct OnboardingView: View {
    @ObservedObject private var s = AppSettings.shared
    @ObservedObject private var pairing = Pairing.shared
    @ObservedObject private var loc = Localizer.shared
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                AppMark(size: 54)
                Text(L("Добро пожаловать в Hydra")).font(.system(size: 20, weight: .semibold))
                Text(L("Многопоточная качалка с авторизованной сессией из браузера."))
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28).padding(.bottom, 22)

            VStack(spacing: 12) {
                extensionStep
                prefsStep
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 18)
            Button(action: finish) {
                Text(L("Начать")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .padding(.horizontal, 24).padding(.bottom, 22)
        }
        .frame(width: 440, height: 500)
    }

    // Шаг 1: расширение + живая проверка связки.
    private var extensionStep: some View {
        card(icon: "puzzlepiece.extension.fill", title: L("Поставьте расширение браузера")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Перехватывает ссылки и передаёт сессию в Hydra."))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                HStack {
                    Button(L("Установить расширение")) { revealBundledExtensions() }
                    Spacer()
                    pairingBadge
                }
            }
        }
    }

    private var pairingBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(pairing.seenExtension ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(pairing.seenExtension ? L("связано") : L("ожидание…"))
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .animation(.easeOut(duration: 0.2), value: pairing.seenExtension)
    }

    // Шаг 2: разрешения/предпочтения.
    private var prefsStep: some View {
        card(icon: "gearshape.fill", title: L("Разрешения")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(L("Запуск при входе в систему"), isOn: $s.launchAtLogin)
                    .font(.system(size: 12.5))
                HStack {
                    Text(L("Уведомления о загрузках и ошибках"))
                        .font(.system(size: 12.5))
                    Spacer()
                    Button(L("Открыть…")) { openNotificationSettings() }
                }
            }
        }
    }

    private func card<Content: View>(icon: String, title: String,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Color.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        onDone()
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
