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

    /// LibreOffice's folders, one per language. Kept here instead of asking the GitHub API, which allows only
    /// 60 requests an hour without signing in; plain file links have no such limit.
    private static let folders = ["af_ZA", "an_ES", "ar", "as_IN", "be_BY", "bg_BG", "bn_BD", "bo", "br_FR", "bs_BA", "ca",
        "ckb", "cs_CZ", "da_DK", "de", "el_GR", "en", "eo", "es", "et_EE", "fa_IR", "fr_FR", "gd_GB", "gl", "gu_IN", "gug",
        "he_IL", "hi_IN", "hr_HR", "hu_HU", "id", "is", "it_IT", "kmr_Latn", "kn_IN", "ko_KR", "lij_IT", "lo_LA", "lt_LT",
        "lv_LV", "mn_MN", "mr_IN", "ne_NP", "nl_NL", "no", "oc_FR", "or_IN", "pa_IN", "pl_PL", "pt_BR", "pt_PT", "ro",
        "ru_RU", "sa_IN", "si_LK", "sk_SK", "sl_SI", "sq_AL", "sr", "sv_SE", "sw_TZ", "ta_IN", "te_IN", "th_TH", "tr_TR",
        "uk_UA", "vi", "zu_ZA"]
    private static let raw = "https://raw.githubusercontent.com/\(repo)/master/"

    static func fetch(_ code: String, into folder: URL) async throws {
        guard let dir = folders.first(where: { $0 == code || $0.hasPrefix(code + "_") }) else { throw CocoaError(.fileNoSuchFile) }
        // Each folder's dictionaries.xcu names its spelling pair: "%origin%/be-official.aff %origin%/be-official.dic".
        let xcu = try await text(raw + dir + "/dictionaries.xcu")
        guard let spell = xcu.components(separatedBy: "<node ").first(where: { $0.contains("DICT_SPELL") }),
              let aff = fileName(in: spell, ext: "aff"), let dic = fileName(in: spell, ext: "dic") else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // macOS names the language after the file, so save it as e.g. be_BY.aff / be_BY.dic.
        let base = dir.contains("_") ? dir : code
        for (name, ext) in [(String(aff), "aff"), (String(dic), "dic")] {
            guard let url = URL(string: raw + dir + "/" + name) else { throw CocoaError(.fileReadInvalidFileName) }
            let (tmp, response) = try await session.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let size = try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int, size <= maxFileSize,
                  Self.looksLikeText(tmp) else { throw CocoaError(.fileReadCorruptFile) }
            let dest = folder.appendingPathComponent("\(base).\(ext)")
            _ = try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        }
    }

    /// "%origin%/be-official.aff" → "be-official.aff"; only plain file names, no paths.
    private static func fileName(in xml: String, ext: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.-"))
        for part in xml.components(separatedBy: "%origin%/").dropFirst() {
            let name = String(part.prefix { $0.unicodeScalars.allSatisfy(allowed.contains) })
            if name.hasSuffix("." + ext), !name.hasPrefix(".") { return name }
        }
        return nil
    }

    private static let session = URLSession(configuration: .ephemeral)

    private static func text(_ link: String) async throws -> String {
        let (data, response) = try await session.data(from: URL(string: link)!)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000,
              let s = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return s
    }

    /// Hunspell files are plain text; refuse anything that isn't (a broken download or an HTML error page).
    private static func looksLikeText(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: 4096)) ?? Data()
        return !head.isEmpty && !head.contains(0) && !(String(data: head, encoding: .utf8) ?? "").lowercased().contains("<html")
    }
}
