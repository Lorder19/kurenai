import AppKit
import ServiceManagement

/// Run from Downloads, macOS launches a read-only randomized copy (App Translocation): login items and the
/// Accessibility grant then point at a path that disappears. Offer to move into /Applications first.
enum AppMover {
    /// An in-app update from the Clippo days lands as Clippo.app. Rename the bundle once and start again
    /// from the new path; the bundle id and signature stay the same, so Accessibility keeps working.
    static func renameLegacyBundleIfNeeded() -> Bool {
        let current = Bundle.main.bundleURL
        guard current.lastPathComponent == "Clippo.app" else { return false }
        let dest = current.deletingLastPathComponent().appendingPathComponent("Kurenai.app")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: dest.path), (try? fm.moveItem(at: current, to: dest)) != nil else { return false }
        let login = SMAppService.mainApp
        if login.status == .enabled {
            try? login.unregister()
            UserDefaults.standard.set(true, forKey: "reRegisterLogin")
        }
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", dest.path]
        try? relaunch.run()
        NSApp.terminate(nil)
        return true
    }

    /// Second half of the rename: point the login item at the new path.
    static func restoreLoginItem() {
        guard UserDefaults.standard.bool(forKey: "reRegisterLogin") else { return }
        UserDefaults.standard.removeObject(forKey: "reRegisterLogin")
        try? SMAppService.mainApp.register()
    }

    /// Returns true when the app is about to relaunch or quit, so launch should stop.
    static func offerMoveIfNeeded() -> Bool {
        let path = Bundle.main.bundlePath
        let apps = ["/Applications/", NSHomeDirectory() + "/Applications/"]
        guard !apps.contains(where: path.hasPrefix) else { return false }
        let translocated = path.contains("/AppTranslocation/")

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("Переместить Kurenai в «Программы»?")
        alert.informativeText = translocated
            ? L("Kurenai запущен прямо из загрузок. Перетащите его в папку «Программы» и откройте оттуда, иначе автозапуск и Универсальный доступ не будут работать.")
            : L("Иначе автозапуск и Универсальный доступ могут перестать работать.")
        if translocated {
            alert.addButton(withTitle: L("Выйти"))
            alert.addButton(withTitle: L("Всё равно продолжить"))
            if alert.runModal() == .alertFirstButtonReturn { NSApp.terminate(nil); return true }
            return false
        }
        alert.addButton(withTitle: L("Переместить"))
        alert.addButton(withTitle: L("Не сейчас"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let dest = URL(fileURLWithPath: "/Applications/Kurenai.app")
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
            try fm.copyItem(at: Bundle.main.bundleURL, to: dest)
        } catch {
            let fail = NSAlert(error: error)
            fail.runModal()
            return false
        }
        try? fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }
}
