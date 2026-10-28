import ApplicationServices
import Carbon

/// Retypes text that was typed in the wrong keyboard layout ("ghbdtn" → "привет", "руддщ" → "hello").
/// The mapping comes from the layouts enabled in macOS, so any pair works (ABC/Russian, US/Ukrainian, …).
struct KeyboardLayout {
    struct Key: Hashable { let code: UInt16; let shift: Bool }

    let id: String
    let charToKey: [Character: Key]
    let keyToChar: [Key: Character]

    init(id: String, keyToChar: [Key: Character]) {
        self.id = id
        self.keyToChar = keyToChar
        var reverse: [Character: Key] = [:]
        // Prefer the unshifted key when two keys give the same character.
        for (key, ch) in keyToChar.sorted(by: { !$0.key.shift && $1.key.shift }) where reverse[ch] == nil {
            reverse[ch] = key
        }
        charToKey = reverse
    }

    /// Reads a layout's printable characters for every key, with and without Shift.
    init?(source: TISInputSource) {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
              let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        let data = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue() as Data
        var map: [Key: Character] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in UInt16(0)..<UInt16(51) {   // the letter, digit and punctuation block
                for shift in [false, true] {
                    var dead: UInt32 = 0, length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let mods: UInt32 = shift ? UInt32(shiftKey >> 8) : 0
                    let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), mods, UInt32(LMGetKbdType()),
                                                OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
                    guard status == noErr, length == 1, let s = String(utf16CodeUnits: chars, count: 1).first,
                          !s.isWhitespace, s.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) else { continue }
                    map[Key(code: code, shift: shift)] = s
                }
            }
        }
        guard map.count > 20 else { return nil }
        self.init(id: id, keyToChar: map)
    }

    /// Keyboard layouts the user can switch between in the menu bar.
    static func enabled() -> [(KeyboardLayout, TISInputSource)] {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.compactMap { src in KeyboardLayout(source: src).map { ($0, src) } }
    }
}

enum LayoutFix {
    /// Characters that only this layout can type (digits and shared punctuation don't count as evidence).
    static func score(_ text: String, in layout: KeyboardLayout, against others: [KeyboardLayout]) -> Int {
        text.filter { ch in layout.charToKey[ch] != nil && !others.contains { $0.charToKey[ch] != nil } }.count
    }

    /// Picks which layout the text was typed in and which one it was meant for.
    static func direction(for text: String, among layouts: [KeyboardLayout]) -> (from: KeyboardLayout, to: KeyboardLayout)? {
        guard layouts.count >= 2 else { return nil }
        let scored = layouts.map { l in (l, score(text, in: l, against: layouts.filter { $0.id != l.id })) }
        guard let from = scored.max(by: { $0.1 < $1.1 }), from.1 > 0 else { return nil }
        // With more than two layouts, the target is the one the converted text fits best.
        let candidates = layouts.filter { $0.id != from.0.id }
        let to = candidates.max { convert(text, from: from.0, to: $0).filter(\.isLetter).count
                                 < convert(text, from: from.0, to: $1).filter(\.isLetter).count }!
        return (from.0, to)
    }

    /// Same physical keys, other layout. Characters the source layout can't type stay as they are.
    static func convert(_ text: String, from: KeyboardLayout, to: KeyboardLayout) -> String {
        String(text.map { ch in from.charToKey[ch].flatMap { to.keyToChar[$0] } ?? ch })
    }
}

/// Reads and replaces the selected text of the focused field through Accessibility, without the clipboard.
/// Native text fields support this; browsers and Electron apps often don't, and the caller falls back to ⌘C/⌘V.
struct FocusedText {
    let element: AXUIElement

    init?(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused, CFGetTypeID(el) == AXUIElementGetTypeID() else { return nil }
        element = el as! AXUIElement
    }

    private func string(_ attr: String) -> String? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attr as CFString, &v) == .success ? v as? String : nil
    }

    var range: CFRange? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &v) == .success,
              let value = v, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &r) ? r : nil
    }

    func select(_ r: CFRange) -> Bool {
        var r = r
        guard let value = AXValueCreate(.cfRange, &r) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    /// The selection, or with nothing selected the word just before the cursor (like Punto Switcher).
    mutating func takeSelectionOrLastWord() -> String? {
        if let sel = string(kAXSelectedTextAttribute), !sel.isEmpty { return sel }
        guard let all = string(kAXValueAttribute), let r = range, r.length == 0, r.location > 0 else { return nil }
        let utf16 = Array(all.utf16)
        guard r.location <= utf16.count else { return nil }
        var start = r.location
        while start > 0, let ch = Unicode.Scalar(utf16[start - 1]), !CharacterSet.whitespacesAndNewlines.contains(ch) { start -= 1 }
        guard start < r.location, select(CFRange(location: start, length: r.location - start)) else { return nil }
        return string(kAXSelectedTextAttribute)
    }

    /// Replaces the selection. Returns false when the app ignores the write.
    func replaceSelection(with text: String) -> Bool {
        let before = string(kAXValueAttribute)
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else { return false }
        // Some apps report success and change nothing; check when we can.
        if let before, let after = string(kAXValueAttribute) { return after != before || before.contains(text) }
        return true
    }
}
