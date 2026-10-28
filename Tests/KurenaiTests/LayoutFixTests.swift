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
