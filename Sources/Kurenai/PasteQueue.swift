import Foundation

struct QueueItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// Cyclic paste queue. Items stay after pasting (shown as used); the cursor wraps to the start after the last one.
/// Items and cursor persist across hide/show (⌘') and app restarts; only clear() empties it.
final class PasteQueue: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var items: [QueueItem] = []
    /// Index of the item the next ⌘V will paste; items before it are "used".
    @Published private(set) var cursor = 0
    var onChange: (() -> Void)?

    private struct Saved: Codable {
        var texts: [String]
        var cursor: Int
    }

    private let fileURL = Store.shared.fileURL.deletingLastPathComponent().appendingPathComponent("queue.json")
    private let ioQueue = DispatchQueue(label: "clipo.queue.io", qos: .utility)

    init() {
        if let raw = try? Data(contentsOf: fileURL), let data = try? (Vault.isEncrypted(raw) ? Vault.open(raw) : raw),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            items = saved.texts.map { QueueItem(text: $0) }
            cursor = items.indices.contains(saved.cursor) ? saved.cursor : 0
            if Vault.isEncrypted(raw) != Settings.shared.encryptStore { changed() } // bring the file in line with the setting
        }
    }

    /// Rewrites the file now, e.g. after encryption was switched on or off.
    func rewrite() { changed() }

    var hasPending: Bool { isActive && !items.isEmpty }

    func isUsed(_ index: Int) -> Bool { index < cursor }

    func activate() {
        isActive = true
        changed(save: false)
    }

    func deactivate() {
        isActive = false
        changed(save: false)
    }

    func clear() {
        items = []
        cursor = 0
        changed()
    }

    /// Waits for pending writes. Used on quit, when an async write would be cut off.
    func flush() { ioQueue.sync {} }

    func push(_ texts: [String]) {
        guard isActive, !texts.isEmpty else { return }
        items.append(contentsOf: texts.map { QueueItem(text: $0) })
        changed()
    }

    func remove(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: i)
        if i < cursor { cursor -= 1 }
        if cursor >= items.count { cursor = 0 }
        changed()
    }

    func setNext(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        cursor = i
        changed()
    }

    func popNext() -> String? {
        guard hasPending else { return nil }
        if !items.indices.contains(cursor) { cursor = 0 }
        let text = items[cursor].text
        cursor = cursor + 1 < items.count ? cursor + 1 : 0
        changed()
        return text
    }

    private func changed(save: Bool = true) {
        onChange?()
        guard save else { return }
        let snapshot = Saved(texts: items.map(\.text), cursor: cursor)
        let url = fileURL
        ioQueue.async {
            guard var data = try? JSONEncoder().encode(snapshot) else { return }
            if Settings.shared.encryptStore {
                guard let sealed = try? Vault.seal(data) else { return }
                data = sealed
            }
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}
