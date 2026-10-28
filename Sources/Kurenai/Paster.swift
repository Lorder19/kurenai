import AppKit
import ApplicationServices

enum Paster {
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func write(image png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        // Some apps only take TIFF.
        if let tiff = NSImage(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    /// With a target, ⌘V is delivered straight to that process: right after a Kurenai panel closes, the
    /// WindowServer still routes keys to Kurenai, which has no window to handle them and beeps.
    static func sendCommandV(to target: NSRunningApplication? = nil) { sendCommand(9, to: target) }
    static func sendCommandC(to target: NSRunningApplication? = nil) { sendCommand(8, to: target) }

    /// Everything on the clipboard, every type of every item, so it can be put back after a temporary write.
    static func snapshot() -> [[NSPasteboard.PasteboardType: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !snapshot.isEmpty else { return }
        pb.writeObjects(snapshot.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
    }

    /// Remote desktop clients (Windows App and friends) forward keys to a Windows machine, where paste is
    /// Ctrl+V and Cmd often arrives as the Windows key. They also sync the clipboard to the remote side a
    /// moment after it changes, so pasting needs a short wait.
    static let remoteDesktopApps: Set<String> = [
        "com.microsoft.rdc.macos",          // Windows App / Microsoft Remote Desktop
        "com.microsoft.rdc.mac",            // older Microsoft Remote Desktop 8
        "com.2X.Client.Mac",                // Parallels Client
        "com.vmware.horizon",               // Omnissa / VMware Horizon
        "com.citrix.receiver.icaviewer.mac", // Citrix Viewer
        "com.devolutions.remotedesktopmanager",
        "com.jumpdesktop.Jump-Desktop",
        "com.microsoft.rdc.osx.beta",
    ]

    static func isRemoteDesktop(_ app: NSRunningApplication?) -> Bool {
        app?.bundleIdentifier.map(remoteDesktopApps.contains) ?? false
    }

    /// Paste into the frontmost app the way it understands.
    static func sendPaste(to target: NSRunningApplication?) {
        if isRemoteDesktop(target) {
            // The client needs a moment after it comes to the front to push the new clipboard to Windows.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { sendControlChord(9) }
        } else {
            sendCommandV(to: target)
        }
    }

    /// Copy the selection in the frontmost app the way it understands.
    static func sendCopy() {
        if isRemoteDesktop(NSWorkspace.shared.frontmostApplication) {
            sendControlChord(8)
        } else {
            sendCommandC()
        }
    }

    /// Remote desktop clients forward individual key presses to Windows and track modifiers by their own
    /// down/up events, not by the flags on the letter. So press Ctrl for real: Ctrl down, key, Ctrl up,
    /// spaced out a little like a person would.
    private static func sendControlChord(_ key: CGKeyCode) {
        let src = CGEventSource(stateID: .privateState)
        let control: CGKeyCode = 59 // left Control
        func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { return }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
        post(control, true, .maskControl)
        usleep(30_000)
        post(key, true, .maskControl)
        usleep(30_000)
        post(key, false, .maskControl)
        usleep(30_000)
        post(control, false, [])
    }

    private static func sendCommand(_ key: CGKeyCode, to target: NSRunningApplication?) {
        sendKey(key, flags: .maskCommand, to: target)
    }

    private static func sendKey(_ key: CGKeyCode, flags: CGEventFlags, to target: NSRunningApplication?) {
        // Private state: the real keyboard's modifiers (a still-held Shift) are not merged into our event.
        let src = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        if let pid = target?.processIdentifier, pid > 0 {
            down?.postToPid(pid)
            up?.postToPid(pid)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
