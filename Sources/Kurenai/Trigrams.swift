import Foundation

/// How typical each three-letter sequence is in Russian and English (log probabilities). "ghbd" scores
/// about −15 in English while "прив" scores −7 in Russian, so a wrong layout shows after four letters,
/// long before the word ends. Data: keyswitcher by Ilya Granin (MIT), as used by Keyboop (MIT); see
/// THIRD_PARTY.md.
final class Trigrams {
    static let shared = Trigrams()

    private let tables: [String: [String: Double]]

    init(tables: [String: [String: Double]]? = nil) {
        self.tables = tables ?? ["ru": Self.load("trigrams_ru"), "en": Self.load("trigrams_en")]
    }

    func knows(_ language: String) -> Bool { !(tables[language]?.isEmpty ?? true) }

    /// Mean log probability of the word's trigrams, padded with spaces; −20 for a sequence never seen.
    func plausibility(_ word: String, language: String) -> Double {
        guard let table = tables[language], !table.isEmpty else { return -.infinity }
        let chars = Array(" " + word.lowercased() + " ")
        guard chars.count >= 3 else { return -.infinity }
        var sum = 0.0
        for i in 0...(chars.count - 3) { sum += table[String(chars[i..<(i + 3)])] ?? -20 }
        return sum / Double(chars.count - 2)
    }

    private static func load(_ name: String) -> [String: Double] {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "json"),
            // `swift test` and debug runs: next to this source file.
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Data/\(name).json"),
        ]
        for url in candidates.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let dict = try? JSONDecoder().decode([String: Double].self, from: data) { return dict }
        }
        NSLog("Kurenai: no \(name).json, layout detection mid-word is off")
        return [:]
    }
}
