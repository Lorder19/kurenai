import AppKit
import Carbon
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int // Carbon flags (cmdKey, shiftKey, …)
    var label: String

    init(keyCode: Int, modifiers: Int, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods = 0, prefix = ""
        if flags.contains(.control) { mods |= controlKey; prefix += "⌃" }
        if flags.contains(.option) { mods |= optionKey; prefix += "⌥" }
        if flags.contains(.shift) { mods |= shiftKey; prefix += "⇧" }
        if flags.contains(.command) { mods |= cmdKey; prefix += "⌘" }
        // A global shortcut without ⌘/⌃/⌥ would swallow ordinary typing.
        guard mods & (cmdKey | controlKey | optionKey) != 0 else { return nil }
        // Taking these globally would break copy/paste/undo/quit everywhere.
        if mods == cmdKey, Self.reserved.contains(Int(event.keyCode)) { return nil }
        let key = Self.keyNames[Int(event.keyCode)]
            ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !key.isEmpty else { return nil }
        self.init(keyCode: Int(event.keyCode), modifiers: mods, label: prefix + key)
    }

    private static let reserved: Set<Int> = [
        kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_A, kVK_ANSI_Q, kVK_ANSI_W,
        kVK_ANSI_S, kVK_ANSI_F, kVK_ANSI_T, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_Tab, kVK_Space,
    ]

    private static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_I: "I", kVK_ANSI_X: "X", kVK_ANSI_C: "C", kVK_ANSI_V: "V", kVK_ANSI_K: "K",
    ]
}

enum ShortcutAction: String, CaseIterable, Codable {
    case history, list, queue, clearQueue, copyLines, fixLayout

    var title: String {
        switch self {
        case .history: L("История")
        case .list: L("Списки")
        case .queue: L("Paste Queue")
        case .clearQueue: L("Очистить очередь")
        case .copyLines: L("Копировать построчно в очередь")
        case .fixLayout: L("Исправить раскладку выделенного")
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .history: Shortcut(keyCode: kVK_ANSI_Semicolon, modifiers: cmdKey, label: "⌘;")
        case .list: Shortcut(keyCode: kVK_ANSI_I, modifiers: cmdKey, label: "⌘I")
        case .queue: Shortcut(keyCode: kVK_ANSI_Quote, modifiers: cmdKey, label: "⌘'")
        case .clearQueue: Shortcut(keyCode: kVK_ANSI_X, modifiers: cmdKey | shiftKey, label: "⇧⌘X")
        case .copyLines: Shortcut(keyCode: kVK_ANSI_C, modifiers: cmdKey | shiftKey, label: "⇧⌘C")
        case .fixLayout: Shortcut(keyCode: kVK_ANSI_K, modifiers: cmdKey | optionKey, label: "⌥⌘K")
        }
    }
}

/// All user preferences, persisted in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    static let historyLimits = [100, 500, 1000, 2000, 5000]

    /// Called whenever shortcuts change so AppDelegate can re-register them.
    var onShortcutsChange: (() -> Void)?
    /// Called while a shortcut is being recorded: global hotkeys must be off or they eat the keypress.
    var onRecording: ((Bool) -> Void)?
    /// The paste queue keeps its own file and must be rewritten too.
    var onEncryptionChange: (() -> Void)?

    @Published private(set) var shortcuts: [ShortcutAction: Shortcut]
    @Published var historyLimit: Int {
        didSet { UserDefaults.standard.set(historyLimit, forKey: "historyLimit"); Store.shared.trimHistory() }
    }
    @Published var excluded: [String] {
        didSet { UserDefaults.standard.set(excluded, forKey: "excludedApps") }
    }

    @Published var encryptStore: Bool {
        didSet { UserDefaults.standard.set(encryptStore, forKey: "encryptStore"); Store.shared.rewrite(); onEncryptionChange?() }
    }
    @Published var clearOnQuit: Bool {
        didSet { UserDefaults.standard.set(clearOnQuit, forKey: "clearOnQuit") }
    }

    private init() {
        let d = UserDefaults.standard
        encryptStore = d.object(forKey: "encryptStore") == nil ? true : d.bool(forKey: "encryptStore")
        clearOnQuit = d.bool(forKey: "clearOnQuit")
        let saved = (d.data(forKey: "shortcuts")).flatMap { try? JSONDecoder().decode([ShortcutAction: Shortcut].self, from: $0) } ?? [:]
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, saved[$0] ?? $0.defaultShortcut) })
        let limit = d.integer(forKey: "historyLimit")
        historyLimit = limit > 0 ? limit : 2000
        excluded = d.stringArray(forKey: "excludedApps") ?? ClipboardMonitor.defaultExcluded
    }

    func shortcut(_ a: ShortcutAction) -> Shortcut { shortcuts[a] ?? a.defaultShortcut }

    func setShortcut(_ s: Shortcut, for a: ShortcutAction) {
        shortcuts[a] = s
        persistShortcuts()
    }

    func resetShortcuts() {
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
        persistShortcuts()
    }

    private func persistShortcuts() {
        UserDefaults.standard.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcuts")
        onShortcutsChange?()
    }

    func toggleExcluded(_ id: String) {
        if let i = excluded.firstIndex(of: id) { excluded.remove(at: i) } else { excluded.append(id) }
    }

    static func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func appIcon(_ id: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

// MARK: - View

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var recording: ShortcutAction?
    @State private var confirmClear = false
    @ObservedObject private var updater = Updater.shared
    @State private var checkUpdates = Updater.shared.enabled

    var body: some View {
        Form {
            Section(L("Основное")) {
                Toggle(L("Запускать при входе в систему"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        let svc = SMAppService.mainApp
                        if on { try? svc.register() } else { try? svc.unregister() }
                        launchAtLogin = svc.status == .enabled
                    }
                Toggle(L("Проверять обновления раз в день"), isOn: $checkUpdates)
                    .onChange(of: checkUpdates) { _, on in updater.enabled = on }
                HStack {
                    Button(L("Проверить сейчас")) { updater.check() }
                    if let r = updater.lastResult { Text(r).foregroundStyle(.secondary) }
                    if let u = updater.available {
                        Button(updater.installing ? L("Обновляю…") : L("Обновить")) { updater.install(u) }
                            .disabled(updater.installing)
                    }
                }
                Picker(L("Хранить в истории"), selection: $settings.historyLimit) {
                    ForEach(Settings.historyLimits, id: \.self) { Text(String(format: L("%d записей"), $0)).tag($0) }
                }
            }

            Section {
                Toggle(L("Шифровать историю на диске"), isOn: $settings.encryptStore)
                Toggle(L("Очищать историю и очередь при выходе"), isOn: $settings.clearOnQuit)
                Button(L("Очистить историю сейчас…"), role: .destructive) { confirmClear = true }
                    .confirmationDialog(L("Удалить всю историю? Списки останутся."), isPresented: $confirmClear) {
                        Button(L("Удалить историю"), role: .destructive) { Store.shared.clearHistory() }
                    }
            } header: {
                Text(L("Приватность"))
            } footer: {
                Text(L("История и картинки хранятся на диске зашифрованными, а не открытым текстом. Ключ лежит рядом, прочитать его может только ваша учётная запись."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        Button(recording == action ? L("Нажмите сочетание…") : settings.shortcut(action).label) {
                            recording = recording == action ? nil : action
                        }
                        .frame(minWidth: 140)
                        .background(recording == action ? ShortcutRecorder { event in record(event, for: action) } : nil)
                    }
                }
            } header: {
                HStack {
                    Text(L("Сочетания клавиш"))
                    Spacer()
                    Button(L("По умолчанию")) { settings.resetShortcuts() }.buttonStyle(.link)
                }
            } footer: {
                Text(L("Системные ⌘C, ⌘V, ⌘X, ⌘Z и подобные занять нельзя. Esc отменяет запись."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(settings.excluded, id: \.self) { id in
                    HStack {
                        if let icon = Settings.appIcon(id) { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                        Text(Settings.appName(id))
                        Spacer()
                        Button { settings.toggleExcluded(id) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help(L("Убрать из исключений"))
                    }
                }
                Button(L("Добавить программу…"), action: addApp)
            } header: {
                Text(L("Не записывать из программ"))
            } footer: {
                Text(L("Если копирование было в одной из этих программ, оно не попадёт в историю. Пароли из менеджеров паролей не записываются никогда."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 760)
        .onChange(of: recording) { _, r in settings.onRecording?(r != nil) }
        .onDisappear { recording = nil }
    }

    private func record(_ event: NSEvent, for action: ShortcutAction) {
        if Int(event.keyCode) == kVK_Escape { recording = nil; return }
        guard let s = Shortcut(event: event) else { NSSound.beep(); return }
        // Swap with whoever already owned this combo instead of registering it twice.
        if let other = ShortcutAction.allCases.first(where: { $0 != action && settings.shortcut($0).keyCode == s.keyCode && settings.shortcut($0).modifiers == s.modifiers }) {
            settings.setShortcut(settings.shortcut(action), for: other)
        }
        settings.setShortcut(s, for: action)
        recording = nil
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !settings.excluded.contains(id) { settings.excluded.append(id) }
        }
    }
}

/// Captures the next keyDown while attached to the view hierarchy.
private struct ShortcutRecorder: NSViewRepresentable {
    let onKey: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            onKey(event)
            return nil
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var monitor: Any? }
}
