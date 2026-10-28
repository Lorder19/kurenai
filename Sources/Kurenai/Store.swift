import Foundation

struct Clip: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var date = Date()
    /// File name in ImageStore when this clip is an image (text is then empty).
    var image: String? = nil
}

struct ClipList: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var items: [Clip]
}

private struct StoreData: Codable {
    var history: [Clip] = []
    var lists: [ClipList] = []
}

final class Store: ObservableObject {
    static let shared = Store()
    // Huge copies would be rewritten into the JSON on every save, so they are skipped.
    static let maxClipBytes = 1_000_000

    @Published private(set) var history: [Clip] = []
    @Published private(set) var lists: [ClipList] = []

    let fileURL: URL
    static let directory: URL = {
        if Demo.isOn { return Demo.directory }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Kurenai", isDirectory: true)
        // The app used to be called Clippo, and Clipo before that; carry its data over once.
        for name in ["Clippo", "Clipo"] where !FileManager.default.fileExists(atPath: dir.path) {
            let old = base.appendingPathComponent(name, isDirectory: true)
            if FileManager.default.fileExists(atPath: old.path) { try? FileManager.default.moveItem(at: old, to: dir) }
        }
        return dir
    }()
    private var pendingSave: DispatchWorkItem?
    private let ioQueue = DispatchQueue(label: "clipo.store.io", qos: .utility)

    private init() {
        let dir = Self.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Older builds created it 0755; temp files from atomic writes must not be visible to other accounts.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        fileURL = dir.appendingPathComponent("store.json")
        guard let raw = try? Data(contentsOf: fileURL) else { return }
        if let data = try? (Vault.isEncrypted(raw) ? Vault.open(raw) : raw),
           let saved = try? JSONDecoder().decode(StoreData.self, from: data) {
            history = saved.history
            lists = saved.lists
        } else {
            // Never overwrite a file we couldn't read (missing key, corruption): set it aside instead.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? FileManager.default.moveItem(at: fileURL, to: dir.appendingPathComponent("store.unreadable-\(stamp).json"))
        }
    }

    /// Sample content for screenshot mode (see Demo).
    func seedDemo(image: Data?) {
        history = Demo.history.map { Clip(text: $0.0, date: Date().addingTimeInterval(-$0.1)) }
        if let image, let name = ImageStore.save(image) {
            history.insert(Clip(text: "", date: Date().addingTimeInterval(-120), image: name), at: 1)
        }
        lists = Demo.lists.map { ClipList(name: $0.0, items: $0.1.map { Clip(text: $0) }) }
    }

    func clearHistory() {
        history.removeAll()
        save()
    }

    func recordImage(_ png: Data) {
        guard png.count <= ImageStore.maxBytes, let name = ImageStore.save(png) else { return }
        history.removeAll { $0.image == name }
        history.insert(Clip(text: "", image: name), at: 0)
        trimHistory()
        save()
    }

    /// Moves an existing clip to the top (re-picking from history).
    func bump(_ clip: Clip) {
        if let name = clip.image {
            history.removeAll { $0.image == name }
            history.insert(Clip(text: "", image: name), at: 0)
            save()
        } else {
            record(clip.text)
        }
    }

    /// Rewrites the file now, e.g. after encryption was switched on or off.
    func rewrite() { save() }

    func record(_ text: String) {
        guard text.utf8.count <= Self.maxClipBytes else { return }
        history.removeAll { $0.image == nil && $0.text == text }
        history.insert(Clip(text: text), at: 0)
        trimHistory()
        save()
    }

    func trimHistory() {
        let limit = Settings.shared.historyLimit
        guard history.count > limit else { return }
        history.removeLast(history.count - limit)
        save()
    }

    func deleteFromHistory(_ id: UUID) {
        history.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    func createList(named name: String, with clip: Clip?) -> UUID {
        let list = ClipList(name: name, items: clip.map { [Clip(text: $0.text)] } ?? [])
        lists.append(list)
        save()
        return list.id
    }

    func renameList(_ id: UUID, to name: String) {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[i].name = name
        save()
    }

    func addText(_ text: String, toList id: UUID) {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[i].items.append(Clip(text: text))
        save()
    }

    func updateText(_ clipID: UUID, inList id: UUID, to text: String) {
        guard let i = lists.firstIndex(where: { $0.id == id }),
              let j = lists[i].items.firstIndex(where: { $0.id == clipID }) else { return }
        lists[i].items[j].text = text
        save()
    }

    func move(_ clipID: UUID, inList id: UUID, by offset: Int) {
        guard let i = lists.firstIndex(where: { $0.id == id }),
              let j = lists[i].items.firstIndex(where: { $0.id == clipID }) else { return }
        let target = j + offset
        guard lists[i].items.indices.contains(target) else { return }
        lists[i].items.swapAt(j, target)
        save()
    }

    func deleteList(_ id: UUID) {
        lists.removeAll { $0.id == id }
        save()
    }

    func add(_ clip: Clip, toList id: UUID) {
        guard let i = lists.firstIndex(where: { $0.id == id }),
              !lists[i].items.contains(where: { $0.text == clip.text }) else { return }
        lists[i].items.append(Clip(text: clip.text))
        save()
    }

    func remove(_ clipID: UUID, fromList id: UUID) {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[i].items.removeAll { $0.id == clipID }
        save()
    }

    func flush() {
        pendingSave?.cancel()
        if Settings.shared.clearOnQuit { history.removeAll() }
        ImageStore.prune(keeping: Set(history.compactMap(\.image)))
        write(StoreData(history: history, lists: lists))
    }

    private func save() {
        pendingSave?.cancel()
        let snapshot = StoreData(history: history, lists: lists)
        ImageStore.prune(keeping: Set(history.compactMap(\.image)))
        let work = DispatchWorkItem { [weak self] in self?.write(snapshot) }
        pendingSave = work
        ioQueue.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func write(_ snapshot: StoreData) {
        guard var data = try? JSONEncoder().encode(snapshot) else { return }
        if Settings.shared.encryptStore {
            guard let sealed = try? Vault.seal(data) else { return } // keep the old file rather than write plaintext
            data = sealed
        }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
