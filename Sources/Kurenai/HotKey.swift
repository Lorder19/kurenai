import Carbon

final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private let keyCode: UInt32
    private let modifiers: UInt32
    private var ref: EventHotKeyRef?

    init(keyCode: Int, modifiers: Int, enabled: Bool = true, handler: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()
        id = HotKey.nextID
        HotKey.nextID += 1
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
        HotKey.handlers[id] = handler
        setEnabled(enabled)
    }

    func setEnabled(_ on: Bool) {
        if on, ref == nil {
            let hkID = EventHotKeyID(signature: OSType(0x434C_504F), id: id) // 'CLPO'
            let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
            if status != noErr {
                // Visible via the `hotkeyFailures` user default; usually means another app owns the combo.
                var failures = UserDefaults.standard.stringArray(forKey: "hotkeyFailures") ?? []
                failures.append("key \(keyCode) mods \(modifiers): \(status)")
                UserDefaults.standard.set(failures, forKey: "hotkeyFailures")
            }
        } else if !on, let r = ref {
            UnregisterEventHotKey(r)
            ref = nil
        }
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            HotKey.handlers[hk.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
