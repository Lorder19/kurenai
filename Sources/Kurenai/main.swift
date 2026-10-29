import AppKit
import Carbon
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store.shared
    private let monitor = ClipboardMonitor()
    private let queue = PasteQueue()
    private let historyModel = HistoryModel()
    private let listModel = ListModel()

    private var historyPanel: FloatingPanel!
    private var listPanel: FloatingPanel!
    private var queuePanel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var pasteNextKey: HotKey!
    private var awaitingSplit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Demo.isOn { startDemo(); return }
        #if DEBUG
        // Test hook, debug builds only: release builds must not let another process drive Accessibility through us.
        if let probe = Demo.argument("KurenaiFixLayoutPid").flatMap(Int32.init), probe > 0 { runLayoutFixProbe(pid: probe); return }
        #endif
        if Self.anotherInstanceKeepsRunning() { NSApp.terminate(nil); return }
        if AppMover.renameLegacyBundleIfNeeded() { return }
        if AppMover.offerMoveIfNeeded() { return }
        AppMover.restoreLoginItem()
        buildPanels()

        monitor.onCopy = { [weak self] in self?.handleCopy($0) }
        monitor.onCopyImage = { [weak self] in self?.store.recordImage($0) }
        monitor.start()

        registerShortcuts()
        startDoubleShift()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.offerDictionaries() }
        Settings.shared.onEncryptionChange = { [weak self] in self?.queue.rewrite() }
        Settings.shared.onShortcutsChange = { [weak self] in self?.registerShortcuts() }
        Settings.shared.onRecording = { [weak self] on in self?.hotKeys.forEach { $0.setEnabled(!on) } }
        // ⌘V is only hijacked while the queue has something to paste; otherwise it stays the normal paste.
        pasteNextKey = HotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey, enabled: false) { [weak self] in
            self?.pasteNextFromQueue()
        }
        queue.onChange = { [weak self] in self?.queueChanged() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }

        setupStatusItem()
        Updater.shared.start()
        let granted = Paster.ensureAccessibility(prompt: false)
        UserDefaults.standard.set(granted, forKey: "accessibilityGranted")
        if !granted || !UserDefaults.standard.bool(forKey: "onboarded") { showOnboarding() }
    }

    private var keyMonitor: Any?

    /// Two copies would both record every copy and fight over the same files. An update or a move to
    /// /Applications starts the new copy while the old one is still quitting, so give it a moment first.
    private static func anotherInstanceKeepsRunning() -> Bool {
        let me = NSRunningApplication.current
        func others() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0 != me && !$0.isTerminated }
        }
        for _ in 0..<30 where !others().isEmpty { usleep(100_000) }
        guard let other = others().first else { return false }
        other.activate()
        return true
    }

    private func startDemo() {
        buildPanels()
        if Demo.panel == "stress" {
            // Load test: records the real clipboard, but only into the throwaway demo folder.
            monitor.onCopy = { [weak self] in self?.store.record($0) }
            monitor.onCopyImage = { [weak self] in self?.store.recordImage($0) }
            monitor.start()
            return
        }
        let icon = NSApp.applicationIconImage.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?
            .representation(using: .png, properties: [:])
        store.seedDemo(image: icon)
        queue.activate()
        queue.push(Demo.queue)
        _ = queue.popNext(); _ = queue.popNext()
        setupStatusItem()
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showDemoPanel() }
    }

    private var tourBackdrop: NSWindow?

    /// Scripted walk through history and the paste queue, for recording a demo GIF without touching the keyboard.
    private func runTour() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        // Dark recording, so the GIF sits well on the site in either theme.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let origin = NSPoint(x: screen.midX - 470, y: screen.midY - 220)
        historyPanel.setFrame(NSRect(x: origin.x, y: origin.y, width: 600, height: 440), display: true)
        queuePanel.setFrame(NSRect(x: origin.x + 620, y: origin.y + 60, width: 320, height: 330), display: true)
        // Tell the recorder where to look, in screen coordinates with the origin at the top left.
        let full = NSScreen.screens[0].frame
        let rect = "\(Int(origin.x - 30)),\(Int(full.maxY - origin.y - 440 - 40)),1000,520"
        try? rect.write(to: Demo.directory.appendingPathComponent("tour-rect"), atomically: true, encoding: .utf8)
        // Plain backdrop so the recording shows Kurenai, not whatever is on your screen.
        let backdrop = NSWindow(contentRect: NSRect(x: origin.x - 30, y: origin.y - 40, width: 1000, height: 520),
                                styleMask: .borderless, backing: .buffered, defer: false)
        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.07, blue: 0.07, alpha: 1).cgColor
        backdrop.contentView = fill
        backdrop.isOpaque = true
        // Above ordinary windows, below the panels (.floating).
        backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        backdrop.isReleasedWhenClosed = false
        backdrop.orderFrontRegardless()
        tourBackdrop = backdrop
        queue.clear()
        var t = 0.0
        func at(_ delay: Double, _ step: @escaping () -> Void) { t += delay; DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: step) }
        at(0.3) { self.historyModel.selection = 0; self.historyPanel.present() }
        for i in 1...3 { at(0.55) { self.historyModel.selection = i } }
        for prefix in ["b", "ba", "bak", "bake", "baker"] { at(0.18) { self.historyModel.query = prefix } }
        at(1.0) { self.historyModel.query = "" }
        at(0.5) { self.historyModel.tab = self.store.lists.first?.id }
        for i in 1...2 { at(0.5) { self.historyModel.selection = i } }
        at(0.9) { self.historyModel.tab = nil; self.queue.activate(); self.queuePanel.orderFrontRegardless() }
        for item in Demo.queue { at(0.45) { self.queue.push([item]) } }
        for _ in 0..<3 { at(0.8) { _ = self.queue.popNext() } }
        at(1.2) { try? "done".write(to: Demo.directory.appendingPathComponent("tour-done"), atomically: true, encoding: .utf8) }
    }

    private func showDemoPanel() {
        switch Demo.panel {
        case "list": toggleList()
        case "queue": queuePanel.present()
        case "settings": openSettings()
        case "onboarding": showOnboarding()
        case "tour": runTour()
        default: toggleHistory()
        }
    }
    private var settingsWindow: NSWindow?

    private func registerShortcuts() {
        hotKeys.forEach { $0.setEnabled(false) }
        UserDefaults.standard.removeObject(forKey: "hotkeyFailures")
        hotKeys = ShortcutAction.allCases.map { action in
            let s = Settings.shared.shortcut(action)
            return HotKey(keyCode: s.keyCode, modifiers: s.modifiers) { [weak self] in self?.perform(action) }
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .history: toggleHistory()
        case .list: toggleList()
        case .queue: toggleQueue()
        case .clearQueue: queue.clear()
        case .copyLines: copyAsLines()
        }
    }

    /// Launching Kurenai again (Spotlight, /Applications) opens settings, since there is no Dock icon to click.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private var onboardingWindow: NSWindow?

    @objc private func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView { [weak self] in
                UserDefaults.standard.set(true, forKey: "onboarded")
                self?.onboardingWindow?.close()
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Kurenai"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            onboardingWindow = w
            // Drop the window on close, so its once-a-second permission check stops too.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.onboardingWindow = nil }
            }
        }
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = L("Настройки Kurenai")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }


    /// Panel shortcuts handled at the window level so they work regardless of SwiftUI focus.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        // By physical key so it works in any layout and with ⌘ still held from ⌘I.
        let digit = Self.digitKeys[Int(event.keyCode)]

        if listPanel.isKeyWindow, listModel.draft == .none {
            let items = listModel.list(in: store)?.items ?? []
            if let n = digit, mods.isSubset(of: .command) {
                let idx = n == 0 ? 9 : n - 1
                if items.indices.contains(idx) { let t = items[idx].text; DispatchQueue.main.async { self.pickFromList(t) } }
                return nil
            }
            if mods == .command, Int(event.keyCode) == kVK_ANSI_N { listModel.beginAdd(); return nil }
            switch Int(event.keyCode) {
            case kVK_Escape: DispatchQueue.main.async { self.listPanel.orderOut(nil) }; return nil
            case kVK_DownArrow: listModel.selection = min(max(items.count - 1, 0), listModel.selection + 1); return nil
            case kVK_UpArrow: listModel.selection = max(0, listModel.selection - 1); return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if items.indices.contains(listModel.selection) { let t = items[listModel.selection].text; DispatchQueue.main.async { self.pickFromList(t) } }
                return nil
            default: break
            }
        }

        return event
    }

    private static let digitKeys: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9, kVK_ANSI_0: 0,
        kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3, kVK_ANSI_Keypad4: 4, kVK_ANSI_Keypad5: 5,
        kVK_ANSI_Keypad6: 6, kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8, kVK_ANSI_Keypad9: 9, kVK_ANSI_Keypad0: 0,
    ]

    private func pickFromList(_ text: String) {
        listPanel.orderOut(nil)
        paste(text)
    }

    private func pickFromHistory(_ clip: Clip) {
        historyPanel.orderOut(nil)
        store.bump(clip)
        if let name = clip.image {
            guard let png = ImageStore.load(name) else { NSSound.beep(); return }
            paste { Paster.write(image: png) }
        } else {
            paste(clip.text)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
        if Settings.shared.clearOnQuit { queue.clear() } // the queue holds copied text too
        queue.flush()
    }

    private func buildPanels() {
        historyPanel = FloatingPanel(
            name: "Kurenai.History", size: NSSize(width: 600, height: 480), minSize: NSSize(width: 420, height: 280),
            takesKey: true, closesOnResign: true,
            content: HistoryView(store: store, model: historyModel,
                                 onPick: { [weak self] in self?.pickFromHistory($0) },
                                 onClose: { [weak self] in self?.historyPanel.orderOut(nil) }))

        listPanel = FloatingPanel(
            name: "Kurenai.List", size: NSSize(width: 360, height: 400), minSize: NSSize(width: 280, height: 220),
            takesKey: true, closesOnResign: true,
            content: ListView(store: store, model: listModel,
                              onPick: { [weak self] in self?.pickFromList($0) },
                              onClose: { [weak self] in self?.listPanel.orderOut(nil) }))

        queuePanel = FloatingPanel(
            name: "Kurenai.Queue", size: NSSize(width: 320, height: 380), minSize: NSSize(width: 260, height: 200),
            takesKey: false, closesOnResign: false,
            content: QueueView(queue: queue, onHide: { [weak self] in self?.queue.deactivate() }))
        queuePanel.animationBehavior = .none
    }

    // MARK: Copy

    private func handleCopy(_ text: String) {
        // The selection copied for a layout fix is ours, not something the user copied.
        if fixingLayout { return }
        store.record(text)
        if awaitingSplit {
            awaitingSplit = false
            if !queue.isActive { queue.activate() }
            queue.push(ClipText.lines(text))
        } else {
            queue.push([text])
        }
    }

    /// ⇧⌘C: copies the selection, then queues each non-empty line separately (a column → N pastes).
    private func copyAsLines() {
        guard Paster.ensureAccessibility(prompt: false) else { NSSound.beep(); return }
        splitToken += 1
        let token = splitToken
        awaitingSplit = true
        // The hotkey fires on key-down. A synthetic ⌘C sent while the real C (or Shift) is still held is
        // read as auto-repeat or as ⇧⌘C (Chrome's Inspect) and silently ignored. Wait for both to go up.
        whenKeysReleased { [weak self] in
            guard let self, token == self.splitToken else { return }
            let before = NSPasteboard.general.changeCount
            // Over remote desktop the copied text has to travel back from the remote machine first.
            let remote = Paster.isRemoteDesktop(NSWorkspace.shared.frontmostApplication)
            if remote {
                // Can't press Ctrl+C for you there (see paste), so wait for your own copy instead.
                Toast.show(L("Нажмите Ctrl+C, строки попадут в очередь"), seconds: 3)
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    if token == self?.splitToken, self?.awaitingSplit == true { self?.awaitingSplit = false }
                }
                return
            }
            Paster.sendCopy()
            // Slow apps sometimes drop the first one; try once more if nothing reached the pasteboard.
            DispatchQueue.main.asyncAfter(deadline: .now() + (remote ? 1.2 : 0.4)) { [weak self] in
                guard let self, token == self.splitToken, self.awaitingSplit,
                      NSPasteboard.general.changeCount == before else { return }
                Paster.sendCopy()
            }
            // Nothing selected → no pasteboard change; don't let the flag swallow a later normal copy.
            DispatchQueue.main.asyncAfter(deadline: .now() + (remote ? 4 : 2)) { [weak self] in
                if token == self?.splitToken, self?.awaitingSplit == true {
                    self?.awaitingSplit = false
                }
            }
        }
    }

    private var splitToken = 0

    private func whenKeysReleased(of action: ShortcutAction = .copyLines, waited: Double = 0, _ run: @escaping () -> Void) {
        let keys = [kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption, Settings.shared.shortcut(action).keyCode]
        let held = keys.contains { CGEventSource.keyState(.hidSystemState, key: CGKeyCode($0)) }
        if !held || waited >= 1.5 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: run); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            self?.whenKeysReleased(of: action, waited: waited + 0.015, run)
        }
    }

    // MARK: Layout fix

    private var fixingLayout = false
    /// Off for the debug probe: it must not change the input language of whoever is using the Mac.
    private var switchesLayout = true
    private let dictionary = SystemDictionary()

    /// Words you keep changing back, kept next to the history (encrypted like it).
    private lazy var layoutMemory: LayoutMemory = {
        let url = Store.directory.appendingPathComponent("layout-memory.json")
        let raw = (try? Data(contentsOf: url)).flatMap { try? (Vault.isEncrypted($0) ? Vault.open($0) : $0) }
        let saved = raw.flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        return LayoutMemory(reverts: saved) { reverts in
            guard var data = try? JSONEncoder().encode(reverts) else { return }
            if Settings.shared.encryptStore { guard let sealed = try? Vault.seal(data) else { return }; data = sealed }
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }()

    /// Double right Shift: copies the selection, retypes it in the other keyboard layout ("ghbdtn" → "привет"), pastes it
    /// over the selection and switches the layout. The clipboard is put back afterwards.
    private func fixLayout(in given: NSRunningApplication? = nil, orSwitch: Bool = false, done: ((String?) -> Void)? = nil) {
        func nothing() {
            if orSwitch { switchToNextLayout() } else { NSSound.beep() }
            done?(nil)
        }
        guard !fixingLayout, Paster.ensureAccessibility(prompt: false) else { nothing(); return }
        let target = given ?? NSWorkspace.shared.frontmostApplication
        // Remote desktop ignores synthetic modifiers, so the copy/paste round trip can't work there.
        guard !Paster.isRemoteDesktop(target) else { nothing(); return }
        // First try Accessibility: no clipboard, no key presses, works in native apps.
        if let pid = target?.processIdentifier, var field = FocusedText(pid: pid),
           let (text, selected) = field.takeSelectionOrLastWord(), !text.isEmpty {
            let layouts = KeyboardLayout.enabled()
            guard let way = LayoutFix.direction(for: text, among: layouts.map(\.0), words: dictionary) else { nothing(); return }
            // Double Shift is a manual command: every word changes, jargon and names included.
            let fixed = LayoutFix.convert(text, from: way.from, to: way.to)
            guard fixed != text else { nothing(); return }
            if field.replaceSelection(with: fixed) {
                if !selected { field.restoreCaret(replaced: text, with: fixed) }
                layoutMemory.noteFix(original: text, fixed: fixed)
                if switchesLayout, let source = layouts.first(where: { $0.0.id == way.to.id })?.1 { TISSelectInputSource(source) }
                done?(fixed)
                return
            }
        }
        // No Accessibility text (some browsers, Electron): fix the word we watched you type, as long as you
        // haven't moved the cursor since. Selections still go through copy and paste below.
        if given == nil, let (word, tail) = lastTypedWord(), !word.isEmpty {
            let layouts = KeyboardLayout.enabled()
            if let way = LayoutFix.direction(for: word, among: layouts.map(\.0), words: dictionary) {
                let fixed = LayoutFix.convert(word, from: way.from, to: way.to)
                if fixed != word, replaceByTyping(old: word + tail, new: fixed + tail) {
                    typing.reset()
                    layoutMemory.noteFix(original: word, fixed: fixed)
                    if switchesLayout, let source = layouts.first(where: { $0.0.id == way.to.id })?.1 { TISSelectInputSource(source) }
                    done?(fixed)
                    return
                }
            }
        }
        let saved = Paster.snapshot()
        fixingLayout = true
        func finish(_ result: String?) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                Paster.restore(saved)
                self?.monitor.ignoreCurrentChange()
                self?.fixingLayout = false
                done?(result)
            }
        }
        whenKeysReleased { [weak self] in
            guard let self else { return }
            let before = NSPasteboard.general.changeCount
            Paster.sendCommandC(to: given)
            self.waitForPasteboard(after: before, until: Date().addingTimeInterval(0.8)) { [weak self] in
                guard let self else { return }
                let layouts = KeyboardLayout.enabled()
                guard NSPasteboard.general.changeCount != before,
                      let text = NSPasteboard.general.string(forType: .string), !text.isEmpty,
                      let way = LayoutFix.direction(for: text, among: layouts.map(\.0), words: self.dictionary) else {
                    if orSwitch { self.switchToNextLayout() } else { NSSound.beep() }
                    finish(nil); return
                }
                let fixed = LayoutFix.convert(text, from: way.from, to: way.to)
                guard fixed != text else {
                    if orSwitch { self.switchToNextLayout() } else { NSSound.beep() }
                    finish(nil); return
                }
                self.layoutMemory.noteFix(original: text, fixed: fixed)
                Paster.write(fixed)
                self.monitor.ignoreCurrentChange()
                Paster.sendCommandV(to: target)
                // Keep typing in the layout the text was meant for.
                if switchesLayout, let source = layouts.first(where: { $0.0.id == way.to.id })?.1 { TISSelectInputSource(source) }
                finish(fixed)
            }
        }
    }

    /// Switches to the next keyboard layout in the menu bar list, like pressing ⌃Space.
    private func switchToNextLayout() {
        let layouts = KeyboardLayout.enabled()
        guard layouts.count > 1 else { return }
        let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let currentID = current.flatMap { TISGetInputSourceProperty($0, kTISPropertyInputSourceID) }
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
        let i = layouts.firstIndex { $0.0.id == currentID } ?? -1
        TISSelectInputSource(layouts[(i + 1) % layouts.count].1)
    }

    /// Once: if a layout's language has no spelling dictionary on this Mac, offer to download it.
    /// Later it's in Settings → Keyboard layout.
    private func offerDictionaries() {
        guard !UserDefaults.standard.bool(forKey: "askedDictionaries") else { return }
        let dicts = Dictionaries.shared
        dicts.refresh()
        guard !dicts.missing.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: "askedDictionaries")
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(format: L("Скачать словарь: %@?"), dicts.missing.map(\.name).joined(separator: ", "))
        alert.informativeText = L("Для этих раскладок в macOS нет словаря. Kurenai может скачать бесплатный словарь LibreOffice с GitHub в ~/Library/Spelling, его увидят и другие программы. Двойной Shift работает и без него.")
        alert.addButton(withTitle: L("Скачать"))
        alert.addButton(withTitle: L("Не сейчас"))
        if alert.runModal() == .alertFirstButtonReturn { dicts.downloadMissing() }
    }

    // MARK: Typing: double right Shift and fixing the layout as you type

    private let keyTap = KeyTap()
    private var shiftDetector = DoubleShiftDetector()

    /// Apps that use Shift-Shift themselves (JetBrains Search Everywhere).
    private static let shiftShiftApps = ["com.jetbrains.", "com.google.android.studio"]

    /// Where fixing while typing would get in the way: shells, code, remote machines.
    private static let noAutoFixApps = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.", "net.kovidgoyal.kitty", "com.mitchellh.ghostty",
        "io.alacritty", "co.zeit.hyper", "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "com.jetbrains.", "com.google.android.studio", "com.sublimetext.", "dev.zed.Zed", "com.panic.Nova",
    ]
    /// Chromium-based apps apply typed text unreliably in mid-word; there we only fix at the Space.
    private static let chromiumApps = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
    ]

    private lazy var typing = TypingEngine(
        layouts: { KeyboardLayout.enabled().map(\.0) },
        currentLayout: { [weak self] in self?.currentLayoutID() },
        words: dictionary, memory: layoutMemory)

    private func startDoubleShift() {
        keyTap.handler = { [weak self] event, type, post in self?.handleKeyEvent(event, type, post) ?? true }
        // Without Accessibility the tap can't be created yet; try again until it's granted.
        if !keyTap.start() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.startDoubleShift() }
        }
    }

    /// Returns false to swallow the key.
    private func handleKeyEvent(_ e: CGEvent, _ type: CGEventType, _ post: (CGEvent) -> Void) -> Bool {
        switch type {
        case .flagsChanged: handleShift(e, post); return true
        case .keyDown: break
        default: shiftDetector.other(); _ = typing.handle(.init(breaksWord: true)); return true
        }
        shiftDetector.other()
        let front = NSWorkspace.shared.frontmostApplication
        let id = front?.bundleIdentifier ?? ""
        guard Settings.shared.autoFix, front != .current, !IsSecureEventInputEnabled(), !Paster.isRemoteDesktop(front),
              !Self.noAutoFixApps.contains(where: id.hasPrefix) else { typing.reset(); return true }
        typing.midWord = !Self.chromiumApps.contains(where: id.hasPrefix)

        let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
        let mods = e.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn])
        var key = TypingEngine.Key()
        switch code {
        case kVK_Delete: key.isBackspace = true
        case kVK_Space: if mods.isEmpty { key.isBoundary = true } else { key.breaksWord = true }
        default:
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            e.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
            let s = String(utf16CodeUnits: chars, count: length)
            if mods.isEmpty, s.count == 1, let c = s.first, !c.isWhitespace,
               c.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0xF700 }) {
                key.char = c
            } else {
                key.breaksWord = true   // Return, Tab, arrows, Escape, shortcuts
            }
        }
        guard case let .replace(delete, text, layout) = typing.handle(key) else { return true }
        (KeyTap.backspaces(delete) + KeyTap.text(text)).forEach(post)
        if let layout, let source = KeyboardLayout.enabled().first(where: { $0.0.id == layout })?.1 {
            TISSelectInputSource(source)
        }
        return false
    }

    private func handleShift(_ e: CGEvent, _ post: (CGEvent) -> Void) {
        let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
        guard code == kVK_RightShift else { shiftDetector.other(); return }
        guard e.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskSecondaryFn]).isEmpty else {
            shiftDetector.other(); return
        }
        let t = ProcessInfo.processInfo.systemUptime
        guard shiftDetector.shift(down: e.flags.contains(.maskShift), at: t) else { return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        // In a password field macOS turns on Secure Input; don't read or retype anything there.
        guard Settings.shared.doubleShift, !IsSecureEventInputEnabled(),
              !Self.shiftShiftApps.contains(where: front.hasPrefix) else { return }
        // Right after an automatic fix, double Shift undoes it and remembers the word.
        if let u = typing.undo() {
            (KeyTap.backspaces(u.delete) + KeyTap.text(u.text)).forEach(post)
            if let source = KeyboardLayout.enabled().first(where: { $0.0.id == u.layout })?.1 { TISSelectInputSource(source) }
            layoutMemory.noteAutoRevert(u.original)
            return
        }
        typing.reset()
        // Manual fix runs after this event is done (it may copy, paste and read the field).
        DispatchQueue.main.async { [weak self] in self?.fixLayout(orSwitch: true) }
    }

    /// The word being typed, for double Shift in apps that don't expose their text.
    private func lastTypedWord() -> (String, String)? {
        typing.word.isEmpty ? nil : (typing.word, "")
    }

    /// Replaces the text just before the cursor: Accessibility when possible, otherwise Backspace + paste.
    @discardableResult
    private func replaceBeforeCaret(in app: NSRunningApplication, old: String, new: String) -> Bool {
        if let field = FocusedText(pid: app.processIdentifier), field.hasText {
            return !field.isSecure && field.replace(old, nearCaretWith: new)
        }
        return replaceByTyping(old: old, new: new)
    }

    private func replaceByTyping(old: String, new: String) -> Bool {
        let saved = Paster.snapshot()
        fixingLayout = true
        Paster.sendBackspaces(old.count)
        Paster.write(new)
        monitor.ignoreCurrentChange()
        Paster.sendCommandV(to: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            Paster.restore(saved)
            self?.monitor.ignoreCurrentChange()
            self?.fixingLayout = false
        }
        return true
    }

    private func currentLayoutID() -> String? {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func waitForPasteboard(after count: Int, until deadline: Date, _ then: @escaping () -> Void) {
        if NSPasteboard.general.changeCount != count || Date() > deadline { then(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.waitForPasteboard(after: count, until: deadline, then)
        }
    }

    #if DEBUG
    /// `Kurenai -KurenaiFixLayoutPid <pid>`: runs one layout fix against that app without focusing it,
    /// prints the result and quits. Lets the feature be tested on a background TextEdit window.
    private func runLayoutFixProbe(pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { print("no app"); exit(2) }
        switchesLayout = false
        // `-KurenaiFixLayoutSelect start,length` selects a range first; `-KurenaiFixLayoutSelect caret,N` puts the cursor at N.
        if let spec = Demo.argument("KurenaiFixLayoutSelect"), let field = FocusedText(pid: pid) {
            let parts = spec.split(separator: ",")
            let caret = parts.first == "caret", n = parts.compactMap { Int($0) }
            _ = field.select(caret ? CFRange(location: n.last ?? 0, length: 0) : CFRange(location: n.first ?? 0, length: n.last ?? 0))
        }
        // `-KurenaiAutoFixWord ghbdtn`: the word was just typed followed by a space; run the while-typing fix.
        if let word = Demo.argument("KurenaiAutoFixWord") {
            let all = KeyboardLayout.enabled().map(\.0)
            guard let from = LayoutFix.direction(for: word, among: all)?.from,
                  let (fixed, _) = AutoFix.decide(word: word, typedIn: from, layouts: all, words: dictionary, memory: layoutMemory) else {
                print("FIXED: <nothing>"); exit(1)
            }
            let ok = replaceBeforeCaret(in: app, old: word + " ", new: fixed + " ")
            print("FIXED:", ok ? fixed : "<replace failed>")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exit(ok ? 0 : 1) }
            return
        }
        fixLayout(in: app) { result in
            print("FIXED:", result ?? "<nothing>")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(result == nil ? 1 : 0) }
        }
    }
    #endif

    // MARK: Paste

    private func pasteNextFromQueue() {
        let position = queue.cursor + 1, total = queue.items.count
        guard let text = queue.popNext() else { return }
        paste(text, remoteNote: String(format: L("Строка %d из %d в буфере. Нажмите Ctrl+V"), min(position, total), total))
    }

    private func paste(_ text: String, remoteNote: String? = nil) {
        paste(remoteNote: remoteNote) { Paster.write(text) }
    }

    private func paste(remoteNote: String? = nil, writing write: () -> Void) {
        write()
        monitor.ignoreCurrentChange()
        guard Paster.ensureAccessibility(prompt: false) else {
            NSLog("Kurenai: paste blocked, no Accessibility permission (text left on clipboard)")
            NSSound.beep()
            DispatchQueue.main.async { self.showOnboarding() }
            return
        }
        // Our synthetic ⌘V must not re-trigger the queue hotkey.
        pasteNextKey.setEnabled(false)
        // macOS makes Kurenai the active app while a panel is key; a ⌘V sent then lands in Kurenai (no window → beep).
        // Hand focus back to where the user was and wait until it's really frontmost.
        let front = NSWorkspace.shared.frontmostApplication
        let target = (front != nil && front != .current) ? front : targetApp
        // Remote desktop clients ignore modifier keys that don't come from a real keyboard, so Kurenai can't
        // press Ctrl+V there. Put the text on the clipboard, go back to the session and ask for Ctrl+V.
        if Paster.isRemoteDesktop(target) {
            if NSApp.isActive { NSApp.deactivate(); target?.activate() }
            Toast.show(remoteNote ?? L("Скопировано. Нажмите Ctrl+V"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.pasteNextKey.setEnabled(self?.queue.hasPending ?? false)
            }
            return
        }
        if NSApp.isActive {
            NSApp.deactivate()
            target?.activate()
        }
        whenTargetIsFrontmost { [weak self] in
            Paster.sendPaste(to: target)
            let settle = Paster.isRemoteDesktop(target) ? 0.6 : 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
                self?.pasteNextKey.setEnabled(self?.queue.hasPending ?? false)
            }
        }
    }

    /// App the user was in when a panel was opened; pastes go back there.
    private var targetApp: NSRunningApplication?

    private func rememberTargetApp() {
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { targetApp = front }
    }

    private func whenTargetIsFrontmost(waited: Double = 0, _ action: @escaping () -> Void) {
        if !NSApp.isActive || waited >= 0.6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: action)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.whenTargetIsFrontmost(waited: waited + 0.02, action)
        }
    }

    // MARK: Panels

    private func toggleHistory() {
        if historyPanel.isVisible { historyPanel.orderOut(nil); return }
        historyModel.query = ""
        historyModel.tab = nil
        historyModel.selection = 0
        rememberTargetApp()
        historyPanel.present()
        historyModel.focusToken += 1
    }

    private func toggleList() {
        if listPanel.isVisible { listPanel.orderOut(nil); return }
        if !store.lists.contains(where: { $0.id == listModel.listID }) {
            listModel.listID = store.lists.first?.id
        }
        listModel.draft = .none
        listModel.draftText = ""
        listModel.selection = 0
        rememberTargetApp()
        listPanel.present()
        listModel.focusToken += 1
    }

    private func toggleQueue() {
        queue.isActive ? queue.deactivate() : queue.activate()
    }

    private func queueChanged() {
        pasteNextKey.setEnabled(queue.hasPending)
        statusItem?.button?.title = queue.isActive ? " \(queue.items.count)" : ""
        if queue.isActive, !queuePanel.isVisible {
            queuePanel.present()
        } else if !queue.isActive, queuePanel.isVisible {
            queuePanel.orderOut(nil)
        }
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.make()
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared
        let recent = Array(store.history.prefix(3))
        if !recent.isEmpty {
            let header = NSMenuItem(title: L("Недавнее"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for clip in recent {
                let title = clip.image == nil ? ClipText.menuTitle(clip.text) : ClipText.imageTitle(clip)
                let item = add(menu, title, nil, #selector(pickRecent(_:)))
                item.representedObject = clip.id
                if let name = clip.image, let thumb = ImageStore.thumbnail(name) {
                    let small = NSImage(size: NSSize(width: 22, height: 16))
                    small.lockFocus()
                    thumb.draw(in: NSRect(x: 0, y: 0, width: 22, height: 16))
                    small.unlockFocus()
                    item.image = small
                }
            }
            menu.addItem(.separator())
        }
        add(menu, recent.isEmpty ? L("История") : L("Вся история"), s.shortcut(.history).label, #selector(menuHistory))
        add(menu, L("Списки"), s.shortcut(.list).label, #selector(menuList))
        add(menu, queue.isActive ? L("Выключить Paste Queue") : L("Включить Paste Queue"), s.shortcut(.queue).label, #selector(menuQueue))
        menu.addItem(.separator())
        if IsSecureEventInputEnabled() {
            // macOS blocks every app's global shortcuts while a password field (or a buggy app) holds Secure Input.
            let item = add(menu, L("⚠️ Включён Secure Input, сочетания не работают"), nil, #selector(noop))
            item.toolTip = L("Пока активно поле пароля, macOS блокирует горячие клавиши всех программ. Переключитесь в другую программу; если не помогло, перезапустите менеджер паролей.")
            menu.addItem(.separator())
        }
        if !Paster.ensureAccessibility(prompt: false) {
            add(menu, L("⚠️ Нет доступа: Универсальный доступ…"), nil, #selector(showOnboarding))
            menu.addItem(.separator())
        }
        if let update = Updater.shared.available {
            add(menu, String(format: L("⬇︎ Обновить до версии %@…"), update.version), nil, #selector(openUpdate))
            menu.addItem(.separator())
        }
        add(menu, L("Настройки…"), "⌘,", #selector(openSettings))
        add(menu, L("Проверить обновления…"), nil, #selector(checkUpdates))
        add(menu, L("Показать файл данных"), nil, #selector(revealData))
        menu.addItem(.separator())
        add(menu, L("Выйти из Kurenai"), nil, #selector(quit))
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ shortcut: String?, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let shortcut {
            let attr = NSMutableAttributedString(string: title + "  ")
            attr.append(NSAttributedString(string: shortcut, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = attr
        }
        menu.addItem(item)
        return item
    }

    @objc private func menuHistory() { toggleHistory() }
    @objc private func menuList() { toggleList() }
    @objc private func menuQueue() { toggleQueue() }
    @objc private func revealData() { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
    @objc private func noop() {}

    /// Menu clicks don't take focus from the frontmost app, so the paste lands where you were typing.
    @objc private func pickRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let clip = store.history.first(where: { $0.id == id }) else { return }
        rememberTargetApp()
        DispatchQueue.main.async { self.pickFromHistory(clip) }
    }
    @objc private func openUpdate() { Updater.shared.available.map { Updater.shared.confirmInstall($0) } }
    @objc private func checkUpdates() { Updater.shared.checkInteractively() }
    @objc private func quit() { NSApp.terminate(nil) }

}

Demo.prepare()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

