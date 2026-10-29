import Foundation

/// Decides, key by key, when a word is being typed in the wrong layout. Pure logic: it gets what you
/// typed and answers with what to do; KeyTap does it on the real keyboard, tests do it on a string.
///
/// Two moments, like Keyboop:
///  • mid-word: from the 4th letter, if the letters are next to impossible in the current language and
///    normal in the other one (trigrams), the word so far is retyped and the layout switches;
///  • at a Space: a word that isn't a word where it was typed but is one in another layout (dictionary,
///    then trigrams for forms the dictionary lacks) is retyped.
final class TypingEngine {
    enum Action: Equatable {
        /// Let the key through.
        case pass
        /// Swallow the key, delete `delete` characters before the cursor, type `text`, switch to `layout`.
        case replace(delete: Int, text: String, layout: String?)
    }

    struct Key {
        var char: Character?          // what the key types in the current layout
        var isBackspace = false
        var isBoundary = false        // Space
        var breaksWord = false        // Return, Tab, arrows, shortcuts, clicks: we lose track of the cursor
    }

    var layouts: () -> [KeyboardLayout]
    var currentLayout: () -> String?
    var words: WordList
    var trigrams: Trigrams
    var memory: LayoutMemory?
    var midWord = true

    /// The word as it is on screen right now.
    private(set) var word = ""
    /// After a mid-word fix: the layout the word now belongs to. Keys that still arrive in the old layout
    /// (macOS switches a beat late) are retyped in this one, so "привtn" never happens.
    private(set) var liveTarget: KeyboardLayout?
    private var liveFrom: KeyboardLayout?
    /// What a fix replaced, for undo: the text as typed, what it became, and the layout it was typed in.
    /// Kept while you finish the fixed word and through the Space after it; the next word clears it.
    private(set) var lastFix: (original: String, fixed: String, from: String)?

    init(layouts: @escaping () -> [KeyboardLayout], currentLayout: @escaping () -> String?,
         words: WordList, trigrams: Trigrams = .shared, memory: LayoutMemory? = nil) {
        self.layouts = layouts
        self.currentLayout = currentLayout
        self.words = words
        self.trigrams = trigrams
        self.memory = memory
    }

    func reset() { word = ""; liveTarget = nil; liveFrom = nil }

    /// After any fix the system layout is switched, and macOS may take a few keys to do it. Until it really
    /// shows the new layout, letters arriving in the old one are retyped, in this word and the next ones.
    private var switching: (from: KeyboardLayout, to: KeyboardLayout)?

    private func healLateLetter(_ c: Character) -> String? {
        guard let s = switching else { return nil }
        if currentLayout() == s.to.id { switching = nil; return nil }
        guard s.from.charToKey[c] != nil, s.to.charToKey[c] == nil else { return nil }
        let fixed = LayoutFix.convert(String(c), from: s.from, to: s.to)
        return fixed == String(c) ? nil : fixed
    }

    func handle(_ key: Key) -> Action {
        if key.breaksWord { reset(); lastFix = nil; return .pass }
        if key.isBackspace {
            if !word.isEmpty { word.removeLast() }
            if word.isEmpty { liveTarget = nil; liveFrom = nil }
            lastFix = nil
            return .pass
        }
        if key.isBoundary { return boundary() }
        guard let c = key.char else { reset(); lastFix = nil; return .pass }

        // Finishing a word that was switched mid-word.
        if let to = liveTarget, let from = liveFrom {
            var typedAs = String(c), shown = String(c), action = Action.pass
            if let healed = healLateLetter(c) {
                // macOS switched a beat late and this letter came in the old layout: retype it.
                shown = healed
                action = .replace(delete: 0, text: shown, layout: nil)
            } else if from.charToKey[c] != nil, to.charToKey[c] == nil {
                shown = LayoutFix.convert(typedAs, from: from, to: to)
                if shown != typedAs { action = .replace(delete: 0, text: shown, layout: nil) }
            } else {
                typedAs = LayoutFix.convert(shown, from: to, to: from)
            }
            word += shown
            if let f = lastFix { lastFix = (f.original + typedAs, f.fixed + shown, f.from) }
            return action
        }

        if word.isEmpty { lastFix = nil }   // a new word: the previous fix can't be undone any more
        if let healed = healLateLetter(c) {
            word += healed
            return .replace(delete: 0, text: healed, layout: nil)
        }
        word.append(c)
        guard midWord, let (from, to) = layoutsFor(word),
              let fixed = Self.midWordFix(word, from: from, to: to, words: words, trigrams: trigrams, memory: memory)
        else { return .pass }
        let original = word
        word = fixed
        liveTarget = to
        liveFrom = from
        switching = (from, to)
        lastFix = (original, fixed, from.id)
        // The key itself is swallowed: delete what's on screen (the word minus this letter), type it fixed.
        return .replace(delete: original.count - 1, text: fixed, layout: to.id)
    }

    private func boundary() -> Action {
        defer { reset() }
        guard !word.isEmpty else { lastFix = nil; return .pass }
        // Fixed mid-word already: the Space just goes through, and undo stays available.
        if liveTarget != nil {
            if let f = lastFix { lastFix = (f.original + " ", f.fixed + " ", f.from) }
            return .pass
        }
        guard let (from, _) = layoutsFor(word),
              let (fixed, to) = Self.boundaryFix(word, from: from, among: layouts(), words: words,
                                                  trigrams: trigrams, memory: memory) else { lastFix = nil; return .pass }
        lastFix = (word + " ", fixed + " ", from.id)
        switching = (from, to)
        return .replace(delete: word.count, text: fixed + " ", layout: to.id)
    }

    /// Undo for the last fix (double Shift right after it). Returns what to do, or nil if nothing to undo.
    func undo() -> (delete: Int, text: String, layout: String, original: String)? {
        guard let f = lastFix else { return nil }
        lastFix = nil
        reset()
        switching = nil
        let original = f.original.trimmingCharacters(in: .whitespaces)
        return (f.fixed.count, f.original, f.from, original)
    }

    /// The layout the word was typed in (the current one, if the word fits it) and the others.
    private func layoutsFor(_ text: String) -> (KeyboardLayout, KeyboardLayout)? {
        let all = layouts()
        guard all.count >= 2 else { return nil }
        let from = all.first { $0.id == currentLayout() && text.allSatisfy($0.charToKey.keys.contains) }
            ?? LayoutFix.direction(for: text, among: all)?.from
        guard let from, let to = all.first(where: { $0.id != from.id && trigrams.knows($0.language) }) ?? all.first(where: { $0.id != from.id })
        else { return nil }
        return (from, to)
    }

    // MARK: Decisions (static, tested directly)

    static let liveImpossible = -13.0
    static let liveMargin = 6.0

    /// Mid-word: only when the letters are next to impossible here and fine there. Strict on purpose.
    static func midWordFix(_ w: String, from: KeyboardLayout, to: KeyboardLayout, words: WordList,
                           trigrams: Trigrams, memory: LayoutMemory?) -> String? {
        guard (4...16).contains(w.count), trigrams.knows(from.language), trigrams.knows(to.language),
              memory?.isKept(w) != true, !(memory?.keepsPrefix(w) ?? false) else { return nil }
        let fixed = LayoutFix.convert(w, from: from, to: to)
        guard fixed != w, fixed.allSatisfy(\.isLetter), w.allSatisfy({ from.charToKey[$0] != nil }) else { return nil }
        if words.isWord(w, language: from.language) { return nil }
        let orig = trigrams.plausibility(w, language: from.language)
        let swap = trigrams.plausibility(fixed, language: to.language)
        return orig <= liveImpossible && swap > orig + liveMargin ? fixed : nil
    }

    /// At a Space: the dictionary first, then trigrams for word forms the dictionary doesn't have.
    static func boundaryFix(_ w: String, from: KeyboardLayout, among layouts: [KeyboardLayout], words: WordList,
                            trigrams: Trigrams, memory: LayoutMemory?) -> (String, KeyboardLayout)? {
        if let d = AutoFix.decide(word: w, typedIn: from, layouts: layouts, words: words, memory: memory) { return d }
        let core = w.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
        guard core.count >= 4, memory?.isKept(w) != true, !words.isWord(core, language: from.language),
              trigrams.knows(from.language) else { return nil }
        for to in layouts where to.id != from.id && trigrams.knows(to.language) {
            let fixed = LayoutFix.convert(w, from: from, to: to)
            let fixedCore = fixed.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            guard fixed != w, fixedCore.allSatisfy({ $0.isLetter || $0 == "-" }) else { continue }
            let orig = trigrams.plausibility(core, language: from.language)
            let swap = trigrams.plausibility(fixedCore, language: to.language)
            if swap > orig + 2 || (orig <= -19 && swap > orig + 1) { return (fixed, to) }
        }
        return nil
    }
}
