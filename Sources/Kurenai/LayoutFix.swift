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
    /// `selected` tells whether you picked the text yourself.
    mutating func takeSelectionOrLastWord() -> (text: String, selected: Bool)? {
        if let sel = string(kAXSelectedTextAttribute), !sel.isEmpty { return (sel, true) }
        guard let all = string(kAXValueAttribute), let r = range, r.length == 0, r.location > 0 else { return nil }
        let utf16 = Array(all.utf16)
        guard r.location <= utf16.count else { return nil }
        var start = r.location
        while start > 0, let ch = Unicode.Scalar(utf16[start - 1]), !CharacterSet.whitespacesAndNewlines.contains(ch) { start -= 1 }
        guard start < r.location, select(CFRange(location: start, length: r.location - start)),
              let word = string(kAXSelectedTextAttribute) else { return nil }
        return (word, false)
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

/// Remembers words you keep changing back. Fix "ytn" → "нет", then fix "нет" → "ytn" again within a minute,
/// and that counts as "this word was right as typed". After three such reverts the word is left alone when
/// a phrase or the last word is fixed. Selecting exactly that word and fixing it still works.
final class LayoutMemory {
    static let threshold = 3
    private static let revertWindow: TimeInterval = 60
    private static let maxWords = 1000

    private(set) var reverts: [String: Int]
    private var last: (original: String, fixed: String, at: Date)?
    private let save: ([String: Int]) -> Void

    init(reverts: [String: Int] = [:], save: @escaping ([String: Int]) -> Void = { _ in }) {
        self.reverts = reverts
        self.save = save
    }

    static func key(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }

    func isKept(_ word: String) -> Bool { (reverts[Self.key(word)] ?? 0) >= Self.threshold }

    /// Call after every fix. Detects a revert of the previous fix and counts the words that were right before.
    func noteFix(original: String, fixed: String, at now: Date = Date()) {
        if let last, now.timeIntervalSince(last.at) < Self.revertWindow,
           original == last.fixed, fixed == last.original {
            for word in last.original.split(whereSeparator: \.isWhitespace) {
                let k = Self.key(String(word))
                if !k.isEmpty { reverts[k, default: 0] += 1 }
            }
            if reverts.count > Self.maxWords {
                // Drop the words that were reverted least, they matter least.
                reverts = Dictionary(uniqueKeysWithValues: reverts.sorted { $0.value > $1.value }.prefix(Self.maxWords).map { ($0.key, $0.value) })
            }
            save(reverts)
            self.last = nil
            return
        }
        last = (original, fixed, now)
    }
}

extension LayoutFix {
    /// Converts word by word, leaving remembered words as typed. With `explicit` (the whole selection is one
    /// word you picked yourself) memory is ignored.
    static func convert(_ text: String, from: KeyboardLayout, to: KeyboardLayout, memory: LayoutMemory?, explicit: Bool) -> String {
        guard let memory, !explicit else { return convert(text, from: from, to: to) }
        var out = "", word = ""
        func flush() { out += memory.isKept(word) ? word : convert(word, from: from, to: to); word = "" }
        for ch in text {
            if ch.isWhitespace { flush(); out.append(ch) } else { word.append(ch) }
        }
        flush()
        return out
    }
}

/// Spots two quick taps of Shift on their own (no other key, no other modifier, no long hold).
struct DoubleShiftDetector {
    var window: TimeInterval = 0.4      // between the two taps
    var maxHold: TimeInterval = 0.3     // a tap, not holding Shift to type capitals
    private var downAt: TimeInterval?
    private var lastTapAt: TimeInterval?
    private var spoiled = false

    /// Shift went down or up, with no other modifier held.
    mutating func shift(down: Bool, at t: TimeInterval) -> Bool {
        if down { downAt = t; spoiled = false; return false }
        guard let d = downAt, !spoiled, t - d <= maxHold else { reset(); return false }
        downAt = nil
        if let prev = lastTapAt, t - prev <= window { lastTapAt = nil; return true }
        lastTapAt = t
        return false
    }

    /// Any other key or modifier cancels: Shift+letter is typing, not a double tap.
    mutating func other() { spoiled = true; lastTapAt = nil }

    private mutating func reset() { downAt = nil; lastTapAt = nil; spoiled = false }
}
