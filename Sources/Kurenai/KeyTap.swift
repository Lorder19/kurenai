import ApplicationServices
import Carbon

/// Intercepts keys system-wide (needs Accessibility). Unlike watching keys, intercepting lets a word be
/// replaced inside the handling of the key that triggered it: the next key you press can't land in the
/// middle of our Backspaces. That is what kept "привет как" from turning into "привкак".
final class KeyTap {
    /// Marks events we post ourselves, so the tap lets them through untouched.
    static let marker: Int64 = 0x4B55_524E

    /// Return nil to swallow the key. `post` inserts events right after it in the input stream.
    var handler: ((CGEvent, CGEventType, _ post: (CGEvent) -> Void) -> Bool)?
    private var port: CFMachPort?

    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { proxy, type, event, info in
            let me = Unmanaged<KeyTap>.fromOpaque(info!).takeUnretainedValue()
            return me.handle(proxy: proxy, type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS switches a slow tap off; switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return Unmanaged.passUnretained(event) }
        let keep = handler?(event, type) { $0.tapPostEvent(proxy) } ?? true
        return keep ? Unmanaged.passUnretained(event) : nil
    }

    // MARK: Events to post

    private static func key(_ code: CGKeyCode, down: Bool) -> CGEvent? {
        let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: code, keyDown: down)
        e?.flags = []
        e?.setIntegerValueField(.eventSourceUserData, value: marker)
        return e
    }

    static func backspaces(_ n: Int) -> [CGEvent] {
        (0..<max(0, n)).flatMap { _ in [key(51, down: true), key(51, down: false)].compactMap { $0 } }
    }

    /// Types text as Unicode, independent of the current layout. Short chunks: some apps drop long ones.
    static func text(_ s: String) -> [CGEvent] {
        var out: [CGEvent] = []
        var chunk: [UniChar] = []
        func flush() {
            guard !chunk.isEmpty, let d = key(0, down: true), let u = key(0, down: false) else { return }
            d.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            u.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            out += [d, u]
            chunk = []
        }
        for ch in s {
            let units = Array(String(ch).utf16)
            if chunk.count + units.count > 1 { flush() }   // one character per event is the safest
            chunk += units
        }
        flush()
        return out
    }
}
