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
