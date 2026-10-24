import AppKit
import Combine
import SwiftUI

/// First-run window: what Kurenai does, the main shortcuts and why it needs Accessibility.
struct OnboardingView: View {
    let onDone: () -> Void
    @ObservedObject private var settings = Settings.shared
    @State private var granted = Paster.ensureAccessibility(prompt: false)
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Добро пожаловать в Kurenai")).font(.title2.bold())
                    Text(L("Kurenai запоминает всё, что вы копируете, и вставляет обратно в одно нажатие."))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                tip(settings.shortcut(.history).label, L("история скопированного, цифры вставляют запись"))
                tip(settings.shortcut(.list).label, L("свои списки фраз для частой вставки"))
                tip(settings.shortcut(.queue).label, L("Paste Queue: копируйте подряд, ⌘V вставляет по очереди"))
                Text(L("Значок Kurenai живёт в строке меню. Сочетания меняются в настройках."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(granted ? .green : .orange).font(.title3)
                        Text(granted ? L("Универсальный доступ включён") : L("Нужен Универсальный доступ")).font(.headline)
                    }
                    Text(L("Без него Kurenai не может нажать ⌘V за вас, и выбранный текст останется только в буфере. Kurenai не читает ваш ввод и ничего никуда не отправляет: история хранится только на этом Mac."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !granted {
                        Text(L("Откройте настройки и включите переключатель напротив Kurenai. Окно само заметит, когда доступ появится."))
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Button(L("Открыть Универсальный доступ")) {
                            Paster.ensureAccessibility(prompt: true) // adds Kurenai to the list
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                        .controlSize(.large)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(granted ? L("Начать") : L("Позже"), action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onReceive(poll) { _ in
            let now = Paster.ensureAccessibility(prompt: false)
            if now != granted {
                granted = now
                UserDefaults.standard.set(now, forKey: "accessibilityGranted")
                if now { NSApp.activate() } // bring the window back from System Settings
            }
        }
    }

    private func tip(_ key: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(key).font(.system(.body, design: .rounded).bold())
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
                .frame(minWidth: 56, alignment: .leading)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
