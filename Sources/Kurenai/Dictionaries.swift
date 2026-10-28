import AppKit

/// Spelling dictionaries for the languages of your keyboard layouts. macOS ships many (Russian, English,
/// Ukrainian…); for the rest Kurenai can fetch the free Hunspell dictionaries LibreOffice publishes on GitHub
/// into ~/Library/Spelling, where macOS picks them up for every app. Nothing is downloaded unless you ask.
final class Dictionaries: ObservableObject {
    static let shared = Dictionaries()

    struct Language: Identifiable, Equatable {
        let code: String       // "ru", "be"
        var id: String { code }
        var name: String { Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code }
    }

    @Published private(set) var missing: [Language] = []
    @Published private(set) var installed: [Language] = []
    @Published private(set) var busy = false
    @Published private(set) var lastError: String?

    /// Where macOS looks for user dictionaries.
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Spelling", isDirectory: true)
    private static let repo = "LibreOffice/dictionaries"
    private static let maxFileSize = 40_000_000

    /// Languages of the enabled layouts, minus English variants already covered by "en".
    static func layoutLanguages() -> [String] {
        Array(Set(KeyboardLayout.enabled().map(\.0.language).filter { !$0.isEmpty })).sorted()
    }

    static func hasDictionary(_ code: String) -> Bool {
        NSSpellChecker.shared.availableLanguages.contains { $0 == code || $0.hasPrefix(code + "_") || $0.hasPrefix(code + "-") }
    }

    func refresh() {
        let langs = Self.layoutLanguages().map(Language.init(code:))
        installed = langs.filter { Self.hasDictionary($0.code) }
        missing = langs.filter { !Self.hasDictionary($0.code) }
    }

    /// Downloads the missing dictionaries. `done` gets the languages that couldn't be found or fetched.
    func downloadMissing(done: (([Language]) -> Void)? = nil) {
        refresh()
        let todo = missing
        guard !todo.isEmpty, !busy else { done?([]); return }
        busy = true
        lastError = nil
        Task {
            var failed: [Language] = []
            for lang in todo {
                do { try await Self.fetch(lang.code, into: Self.folder) } catch { failed.append(lang) }
            }
            // The spelling service reads ~/Library/Spelling when it starts; let it restart and see the new files.
            let restart = Process()
            restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            restart.arguments = ["AppleSpell"]
            try? restart.run()
            restart.waitUntilExit()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let notFetched = failed
            await MainActor.run {
                self.busy = false
                self.refresh()
                self.lastError = notFetched.isEmpty ? nil : notFetched.map(\.name).joined(separator: ", ")
                done?(notFetched)
            }
        }
    }

    // MARK: Download

    private struct Entry: Decodable { let name: String; let type: String; let size: Int; let download_url: String? }

    static func fetch(_ code: String, into folder: URL) async throws {
        // LibreOffice keeps each language in a folder named after it: "be_BY", "kk", "sr"…
        let root: [Entry] = try await get("https://api.github.com/repos/\(repo)/contents")
        guard let dir = root.first(where: { $0.type == "dir" && ($0.name == code || $0.name.hasPrefix(code + "_")) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let files: [Entry] = try await get("https://api.github.com/repos/\(repo)/contents/\(dir.name)")
        // A spelling pair is name.aff + name.dic; hyphenation (hyph_*) and thesaurus (th_*) files are skipped.
        let affs = files.filter { $0.name.hasSuffix(".aff") && !$0.name.hasPrefix("hyph") && !$0.name.hasPrefix("th_") }
        func dicFor(_ aff: Entry) -> Entry? { files.first { $0.name == aff.name.dropLast(4) + ".dic" } }
        guard let aff = affs.first(where: { dicFor($0) != nil }), let dic = dicFor(aff) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // macOS names the language after the file, so save it as e.g. be_BY.aff / be_BY.dic.
        let base = dir.name.contains("_") ? dir.name : code
        for (entry, ext) in [(aff, "aff"), (dic, "dic")] {
            guard entry.size <= maxFileSize, let link = entry.download_url, let url = URL(string: link),
                  url.scheme == "https", url.host == "raw.githubusercontent.com" else { throw CocoaError(.fileReadTooLarge) }
            let (tmp, response) = try await session.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let size = try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int, size <= maxFileSize,
                  Self.looksLikeText(tmp) else { throw CocoaError(.fileReadCorruptFile) }
            let dest = folder.appendingPathComponent("\(base).\(ext)")
            _ = try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        }
    }

    private static let session = URLSession(configuration: .ephemeral)

    private static func get<T: Decodable>(_ link: String) async throws -> T {
        var req = URLRequest(url: URL(string: link)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Hunspell files are plain text; refuse anything that isn't (a broken download or an HTML error page).
    private static func looksLikeText(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: 4096)) ?? Data()
        return !head.isEmpty && !head.contains(0) && !(String(data: head, encoding: .utf8) ?? "").lowercased().contains("<html")
    }
}
