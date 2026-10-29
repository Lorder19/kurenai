import XCTest
@testable import Kurenai

/// Types a phrase key by key, the way a person would, into a fake text field, and checks what ends up
/// on screen. The "system" layout switches only after `lag` more keys, like the real one sometimes does.
final class TypingSimulationTests: XCTestCase {
    lazy var en = KeyboardLayout.installed("com.apple.keylayout.ABC")!
    lazy var ru = KeyboardLayout.installed("com.apple.keylayout.RussianWin")!

    struct Sim {
        var screen = ""
        var layout: String
        var pendingLayout: (id: String, after: Int)?
        let engine: TypingEngine
    }

    func makeSim(start: String, memory: LayoutMemory? = nil) -> Sim {
        let box = Box(start)
        let pair = [en, ru]
        let engine = TypingEngine(layouts: { pair }, currentLayout: { box.value }, words: SystemDictionary(), memory: memory)
        sims[ObjectIdentifier(engine)] = box
        return Sim(layout: start, engine: engine)
    }
    final class Box { var value: String; init(_ v: String) { value = v } }
    var sims: [ObjectIdentifier: Box] = [:]

    /// `intended` is what the person means to write; each character is typed with the key that gives it
    /// in its own language, but produces whatever the system layout says.
    func type(_ intended: String, into sim: inout Sim, lag: Int = 0) {
        for ch in intended {
            let box = sims[ObjectIdentifier(sim.engine)]!
            box.value = sim.layout
            if ch == " " {
                apply(sim.engine.handle(.init(char: nil, isBoundary: true)), key: " ", sim: &sim, lag: lag)
                continue
            }
            let home = ru.charToKey[ch] != nil && en.charToKey[ch] == nil ? ru : (en.charToKey[ch] != nil ? en : ru)
            guard let key = home.charToKey[ch] else { XCTFail("no key for \(ch)"); return }
            let current = sim.layout == ru.id ? ru : en
            let produced = current.keyToChar[key] ?? ch
            apply(sim.engine.handle(.init(char: produced)), key: produced, sim: &sim, lag: lag)
        }
    }

    func apply(_ action: TypingEngine.Action, key: Character, sim: inout Sim, lag: Int) {
        if let p = sim.pendingLayout {
            if p.after <= 0 { sim.layout = p.id; sim.pendingLayout = nil } else { sim.pendingLayout = (p.id, p.after - 1) }
        }
        switch action {
        case .pass: sim.screen.append(key)
        case let .replace(delete, text, layout):
            sim.screen.removeLast(min(delete, sim.screen.count))
            sim.screen += text
            if let layout {
                if lag == 0 { sim.layout = layout } else { sim.pendingLayout = (layout, lag - 1) }
            }
        }
    }

    func testTheBugReport() {
        // "ghbdtn rfr" used to end up as "привкак".
        var sim = makeSim(start: en.id)
        type("привет как ", into: &sim)
        XCTAssertEqual(sim.screen, "привет как ")
        XCTAssertEqual(sim.layout, ru.id)
    }

    func testSwitchesInTheMiddleOfTheWord() {
        var sim = makeSim(start: en.id)
        type("прив", into: &sim)
        XCTAssertEqual(sim.screen, "прив", "fixed on the 4th letter, before any Space")
        XCTAssertEqual(sim.layout, ru.id)
        type("ет", into: &sim)
        XCTAssertEqual(sim.screen, "привет")
    }

    func testLateLayoutSwitchIsHealed() {
        // The system keeps the old layout for two more keys: those letters arrive as Latin and get fixed.
        var sim = makeSim(start: en.id)
        type("привет как дела ", into: &sim, lag: 2)
        XCTAssertEqual(sim.screen, "привет как дела ")
    }

    func testEnglishTypedInRussian() {
        var sim = makeSim(start: ru.id)
        type("hello world ", into: &sim)
        XCTAssertEqual(sim.screen, "hello world ")
        XCTAssertEqual(sim.layout, en.id)
    }

    func testLongPhrase() {
        var sim = makeSim(start: en.id)
        type("и почемуто двойной шифт не работает никаким образом ", into: &sim)
        XCTAssertEqual(sim.screen, "и почемуто двойной шифт не работает никаким образом ")
    }

    func testCorrectTypingIsUntouched() {
        var ruSim = makeSim(start: ru.id)
        type("привет как дела ", into: &ruSim)
        XCTAssertEqual(ruSim.screen, "привет как дела ")
        var enSim = makeSim(start: en.id)
        type("hello world this is fine ", into: &enSim)
        XCTAssertEqual(enSim.screen, "hello world this is fine ")
    }

    func testUndoAfterAFix() {
        var sim = makeSim(start: en.id)
        type("ghbdtn", into: &sim)            // typed literally in English: becomes привет mid-word
        let shown = sim.screen
        XCTAssertNotEqual(shown, "ghbdtn")
        let u = sim.engine.undo()
        XCTAssertNotNil(u)
        XCTAssertEqual(u?.text, "ghbdtn")
        XCTAssertEqual(u?.delete, shown.count)
    }

    func testBackspaceKeepsTrack() {
        var sim = makeSim(start: en.id)
        type("прив", into: &sim)
        _ = sim.engine.handle(.init(char: nil, isBackspace: true)); sim.screen.removeLast()
        type("вет ", into: &sim)
        XCTAssertEqual(sim.screen, "привет ")
    }
}
