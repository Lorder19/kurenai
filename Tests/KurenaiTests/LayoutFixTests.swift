import Carbon
import XCTest
@testable import Kurenai

final class LayoutFixTests: XCTestCase {
    // The two layouts on a typical Russian Mac, read from macOS itself.
    lazy var layouts = KeyboardLayout.enabled().map(\.0)
    func layout(_ suffix: String) throws -> KeyboardLayout {
        try XCTUnwrap(layouts.first { $0.id.hasSuffix(suffix) }, "layout \(suffix) is not enabled")
    }

    func fix(_ text: String) -> String? {
        guard let d = LayoutFix.direction(for: text, among: layouts) else { return nil }
        return LayoutFix.convert(text, from: d.from, to: d.to)
    }

    func testEnglishTypedAsRussian() throws {
        _ = try layout("ABC"); _ = try layout("RussianWin")
        XCTAssertEqual(fix("ghbdtn"), "привет")
        XCTAssertEqual(fix("Ghbdtn? rfr ltkf&"), "Привет, как дела?")
        XCTAssertEqual(fix("Ghbdtn, rfr ltkf?"), "Приветб как дела,")  // literal: those keys type б and , in Russian
    }

    func testRussianTypedAsEnglish() throws {
        XCTAssertEqual(fix("руддщ цщкдв"), "hello world")
        XCTAssertEqual(fix("Руддщ"), "Hello")
    }

    func testDigitsAndSpacesStay() throws {
        XCTAssertEqual(fix("ghbdtn 2026"), "привет 2026")
    }

    func testAllLettersRoundTrip() throws {
        let ru = try layout("RussianWin"), en = try layout("ABC")
        let text = "йцукенгшщзхъфывапролджэячсмитьбюё"
        XCTAssertEqual(LayoutFix.convert(LayoutFix.convert(text, from: ru, to: en), from: en, to: ru), text)
        XCTAssertEqual(LayoutFix.convert(text.uppercased(), from: ru, to: en).count, text.count)
    }

    func testNothingToFix() {
        XCTAssertNil(fix("2026 = 42"))
    }
}

final class LayoutBothWaysTests: XCTestCase {
    lazy var layouts = KeyboardLayout.enabled().map(\.0)
    func fix(_ text: String) -> String? {
        guard let d = LayoutFix.direction(for: text, among: layouts) else { return nil }
        return LayoutFix.convert(text, from: d.from, to: d.to)
    }

    func testRussianToEnglishAndBack() {
        let pairs = [
            ("ghbdtn", "привет"), ("Ghbdtn? rfr ltkf&", "Привет, как дела?"), ("ckjdj", "слово"),
            ("Vjcrdf", "Москва"), ("CJJ<OTYBT", "СООБЩЕНИЕ"), ("'nj ntcn", "это тест"),
            ("c[tvf", "схема"), ("j,]trn", "объект"),
        ]
        for (en, ru) in pairs {
            XCTAssertEqual(fix(en), ru, "en→ru \(en)")
            XCTAssertEqual(fix(ru), en, "ru→en \(ru)")
        }
    }

    func testYoRoundTrips() {
        // Where ё sits depends on the keyboard (§ on ISO Macs, ` on ANSI), so check the round trip only.
        let typedWrong = fix("ёлка")
        XCTAssertNotNil(typedWrong)
        XCTAssertEqual(typedWrong.flatMap(fix), "ёлка")
    }

    func testEnglishWordsTypedInRussian() {
        for (ru, en) in [("руддщ", "hello"), ("цщкдв", "world"), ("ьфсищщл", "macbook"), ("Лгкутфш", "Kurenai")] {
            XCTAssertEqual(fix(ru), en)
            XCTAssertEqual(fix(en), ru)
        }
    }

    func testMixedTextFollowsTheMajority() {
        // Mostly Latin gibberish with one Russian word: the Latin part is what was mistyped.
        XCTAssertEqual(fix("ghbdtn vbh"), "привет мир")
    }
}

final class LayoutMemoryTests: XCTestCase {
    func testThreeRevertsKeepTheWord() {
        var saved: [String: Int] = [:]
        let m = LayoutMemory { saved = $0 }
        let t0 = Date()
        for i in 0..<3 {
            let t = t0.addingTimeInterval(Double(i) * 100)
            m.noteFix(original: "ytn", fixed: "нет", at: t)
            XCTAssertFalse(m.isKept("ytn"))
            m.noteFix(original: "нет", fixed: "ytn", at: t.addingTimeInterval(5))   // changed it back
        }
        XCTAssertTrue(m.isKept("ytn"))
        XCTAssertTrue(m.isKept("YTN,"))
        XCTAssertEqual(saved["ytn"], 3)
    }

    func testSlowOrUnrelatedFixesDontCount() {
        let m = LayoutMemory()
        let t = Date()
        m.noteFix(original: "ytn", fixed: "нет", at: t)
        m.noteFix(original: "нет", fixed: "ytn", at: t.addingTimeInterval(120))     // too late
        m.noteFix(original: "ghbdtn", fixed: "привет", at: t.addingTimeInterval(130))
        m.noteFix(original: "руддщ", fixed: "hello", at: t.addingTimeInterval(131)) // a different fix
        XCTAssertEqual(m.reverts, [:])
    }

    func testRememberedWordsStayInPhrases() throws {
        let layouts = KeyboardLayout.enabled().map(\.0)
        let ru = try XCTUnwrap(layouts.first { $0.id.hasSuffix("RussianWin") }), en = try XCTUnwrap(layouts.first { $0.id.hasSuffix("ABC") })
        let m = LayoutMemory(reverts: ["iphone": 3])
        XCTAssertEqual(LayoutFix.convert("vjq iphone", from: en, to: ru, memory: m, explicit: false), "мой iphone")
        XCTAssertEqual(LayoutFix.convert("iphone", from: en, to: ru, memory: m, explicit: true), "шзрщту")
    }
}

final class DoubleShiftTests: XCTestCase {
    func testTwoQuickTaps() {
        var d = DoubleShiftDetector()
        XCTAssertFalse(d.shift(down: true, at: 0.00))
        XCTAssertFalse(d.shift(down: false, at: 0.08))
        XCTAssertFalse(d.shift(down: true, at: 0.20))
        XCTAssertTrue(d.shift(down: false, at: 0.28))
    }

    func testTooSlow() {
        var d = DoubleShiftDetector()
        _ = d.shift(down: true, at: 0); _ = d.shift(down: false, at: 0.1)
        _ = d.shift(down: true, at: 0.9)
        XCTAssertFalse(d.shift(down: false, at: 1.0))
    }

    func testShiftHeldForCapitalsIsNotATap() {
        var d = DoubleShiftDetector()
        _ = d.shift(down: true, at: 0); _ = d.shift(down: false, at: 0.1)
        _ = d.shift(down: true, at: 0.2); d.other()             // Shift+A
        XCTAssertFalse(d.shift(down: false, at: 0.3))
        _ = d.shift(down: true, at: 1.0)
        XCTAssertFalse(d.shift(down: false, at: 1.6))          // held too long
    }

    func testTypingBetweenTapsCancels() {
        var d = DoubleShiftDetector()
        _ = d.shift(down: true, at: 0); _ = d.shift(down: false, at: 0.1)
        d.other()
        _ = d.shift(down: true, at: 0.2)
        XCTAssertFalse(d.shift(down: false, at: 0.3))
    }

    func testLeftShiftBetweenTapsCancels() {
        // Only the right Shift counts; the app feeds a left Shift as `other()`.
        var d = DoubleShiftDetector()
        _ = d.shift(down: true, at: 0); _ = d.shift(down: false, at: 0.1)
        d.other()
        _ = d.shift(down: true, at: 0.2)
        XCTAssertFalse(d.shift(down: false, at: 0.25))
    }

    func testThirdTapStartsOver() {
        var d = DoubleShiftDetector()
        _ = d.shift(down: true, at: 0); _ = d.shift(down: false, at: 0.05)
        _ = d.shift(down: true, at: 0.1); XCTAssertTrue(d.shift(down: false, at: 0.15))
        _ = d.shift(down: true, at: 0.2); XCTAssertFalse(d.shift(down: false, at: 0.25))
    }
}

/// The mapping must come from the layouts themselves, for any pair, not from a built-in Russian table.
final class LayoutPairsTests: XCTestCase {
    func pair(_ a: String, _ b: String) throws -> (KeyboardLayout, KeyboardLayout) {
        (try XCTUnwrap(KeyboardLayout.installed("com.apple.keylayout." + a), a),
         try XCTUnwrap(KeyboardLayout.installed("com.apple.keylayout." + b), b))
    }

    /// Every character typeable in both layouts goes there and back unchanged.
    func roundTrip(_ a: KeyboardLayout, _ b: KeyboardLayout, file: StaticString = #filePath, line: UInt = #line) {
        var checked = 0
        for (key, ch) in a.keyToChar where key.mods < 2 && b.keyToChar[key] != nil {
            let there = LayoutFix.convert(String(ch), from: a, to: b)
            let back = LayoutFix.convert(there, from: b, to: a)
            XCTAssertEqual(back, String(a.keyToChar[a.charToKey[ch]!]!), "\(a.id) \(ch) → \(there)", file: file, line: line)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 80, file: file, line: line)
    }

    func testAbcRussianPC() throws {
        let (en, ru) = try pair("ABC", "RussianWin")
        roundTrip(en, ru); roundTrip(ru, en)
        XCTAssertEqual(LayoutFix.convert("ghbdtn", from: en, to: ru), "привет")
    }

    func testAbcRussianMac() throws {
        // The Mac "Russian" layout puts punctuation elsewhere than "Russian – PC"; the mapping must follow it.
        let (en, ru) = try pair("ABC", "Russian")
        roundTrip(en, ru); roundTrip(ru, en)
        XCTAssertEqual(LayoutFix.convert("ghbdtn", from: en, to: ru), "привет")
        let pc = try XCTUnwrap(KeyboardLayout.installed("com.apple.keylayout.RussianWin"))
        XCTAssertNotEqual(ru.charToKey[","], pc.charToKey[","], "comma sits on different keys in the two Russian layouts")
    }

    func testUsUkrainian() throws {
        let (en, ua) = try pair("US", "Ukrainian-PC")
        roundTrip(en, ua); roundTrip(ua, en)
        XCTAssertEqual(LayoutFix.convert("ghbdsn", from: en, to: ua), "привіт")
    }

    func testOptionLayerIsRead() throws {
        let (en, _) = try pair("ABC", "RussianWin")
        XCTAssertTrue(en.keyToChar.keys.contains { $0.mods >= 2 }, "Option characters are part of the map")
        XCTAssertEqual(en.charToKey["a"]?.mods, 0, "plain key wins over Option for the same character")
    }

    func testKeyboardTypeMatters() throws {
        // On an ISO keyboard (the one in this Mac) the extra § key (code 10) exists and gets its character
        // from the layout itself; on ANSI it isn't there at all.
        let abc = try XCTUnwrap(KeyboardLayout.installed("com.apple.keylayout.ABC"))
        let ru = try XCTUnwrap(KeyboardLayout.installed("com.apple.keylayout.RussianWin"))
        if KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardISO {
            XCTAssertNotNil(abc.keyToChar[.init(code: 10, mods: 0)])
            XCTAssertEqual(ru.keyToChar[.init(code: 10, mods: 0)], "ё")
        }
    }
}

final class DictionaryTests: XCTestCase {
    lazy var en = KeyboardLayout.installed("com.apple.keylayout.ABC")!
    lazy var ru = KeyboardLayout.installed("com.apple.keylayout.RussianWin")!
    let dict = SystemDictionary()

    func testLayoutsKnowTheirLanguage() {
        XCTAssertEqual(en.language, "en")
        XCTAssertEqual(ru.language, "ru")
    }

    func testSystemDictionary() {
        XCTAssertTrue(dict.isWord("привет", language: "ru"))
        XCTAssertTrue(dict.isWord("hello", language: "en"))
        XCTAssertTrue(dict.isWord("London", language: "en"))
        XCTAssertFalse(dict.isWord("ghbdtn", language: "en"))
        XCTAssertFalse(dict.isWord("руддщ", language: "ru"))
    }

    func testRealWordsInAPhraseStay() {
        // "hello" typed right, "vbh" typed in the wrong layout: only the second one changes.
        XCTAssertEqual(LayoutFix.smartConvert("hello vbh", from: en, to: ru, words: dict, memory: nil, explicit: false), "hello мир")
        XCTAssertEqual(LayoutFix.smartConvert("Ghbdtn? rfr ltkf&", from: en, to: ru, words: dict, memory: nil, explicit: false), "Привет, как дела?")
        XCTAssertEqual(LayoutFix.smartConvert("руддщ цщкдв", from: ru, to: en, words: dict, memory: nil, explicit: false), "hello world")
    }

    func testCorrectLastWordIsLeftAlone() {
        // Double Shift after a word that is already right: nothing to fix (the app then just switches the layout).
        XCTAssertEqual(LayoutFix.smartConvert("hello", from: en, to: ru, words: dict, memory: nil, explicit: false), "hello")
        XCTAssertEqual(LayoutFix.smartConvert("привет", from: ru, to: en, words: dict, memory: nil, explicit: false), "привет")
    }

    func testSelectedWordAlwaysConverts() {
        XCTAssertEqual(LayoutFix.smartConvert("hello", from: en, to: ru, words: dict, memory: nil, explicit: true), "руддщ")
    }

    func testGibberishBothWaysStillConverts() {
        XCTAssertEqual(LayoutFix.smartConvert("ghbdtnbr", from: en, to: ru, words: dict, memory: nil, explicit: false), "приветик")
    }

    func testThirdLayoutPickedByDictionary() throws {
        let ua = try XCTUnwrap(KeyboardLayout.installed("com.apple.keylayout.Ukrainian-PC"))
        XCTAssertEqual(ua.language, "uk")
        // "ghbdsn" is "привіт" in Ukrainian and "привыт" (not a word) in Russian.
        let way = try XCTUnwrap(LayoutFix.direction(for: "ghbdsn", among: [en, ru, ua], words: dict))
        XCTAssertEqual(way.to.id, ua.id)
    }
}
