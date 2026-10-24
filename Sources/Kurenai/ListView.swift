import SwiftUI

final class ListModel: ObservableObject {
    enum Draft: Equatable { case none, add, edit(UUID) }

    @Published var listID: UUID? {
        didSet { if !Demo.isOn { UserDefaults.standard.set(listID?.uuidString, forKey: "lastListID") } }
    }
    @Published var selection = 0
    @Published var draft: Draft = .none
    @Published var draftText = ""
    @Published var focusToken = 0

    init() {
        listID = UserDefaults.standard.string(forKey: "lastListID").flatMap(UUID.init(uuidString:))
    }

    func list(in store: Store) -> ClipList? {
        store.lists.first { $0.id == listID } ?? store.lists.first
    }

    func beginAdd() {
        draft = .add
        draftText = ""
        focusToken += 1
    }
}

struct ListView: View {
    @ObservedObject var store: Store
    @ObservedObject var model: ListModel
    let onPick: (String) -> Void
    let onClose: () -> Void

    // Digits/arrows/esc are handled by AppDelegate's key monitor: SwiftUI focus on a plain view
    // only works when the system "Keyboard navigation" setting is on.
    @FocusState private var draftFocused: Bool

    private var list: ClipList? { model.list(in: store) }

    var body: some View {
        let items = list?.items ?? []
        VStack(spacing: 0) {
            PanelHeader(icon: "list.number") {
                listMenu
            } trailing: {
                IconButton(symbol: "plus", help: L("Добавить строку (⌘N)")) { begin(.add) }
            }

            Divider().opacity(0.6)

            ZStack {
                if items.isEmpty {
                    EmptyState(icon: "text.badge.plus", title: L("Список пуст"),
                               subtitle: L("Жми + или ⌘N, чтобы добавить строку"))
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { idx, clip in
                                    row(idx, clip, total: items.count)
                                }
                            }
                            .padding(8)
                        }
                        .onChange(of: model.selection) { _, new in
                            if items.indices.contains(new) { proxy.scrollTo(items[new].id) }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if model.draft != .none { draftBar }

            HintBar(hints: [("1–0", L("вставить")), ("⌘N", L("добавить")), ("esc", L("закрыть"))])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.2), value: model.draft)
        .onChange(of: model.focusToken) { draftFocused = model.draft != .none }
    }

    private var listMenu: some View {
        Menu {
            ForEach(store.lists) { l in
                Button(l.name) { model.listID = l.id; model.selection = 0 }
            }
            Divider()
            Button(L("Новый список…")) {
                if let name = Prompt.text(title: L("Новый список")) {
                    model.listID = store.createList(named: name, with: nil)
                }
            }
            if let list {
                Button(String(format: L("Переименовать «%@»…"), list.name)) {
                    if let name = Prompt.text(title: L("Переименовать список"), initial: list.name) {
                        store.renameList(list.id, to: name)
                    }
                }
                Button(String(format: L("Удалить «%@»…"), list.name), role: .destructive) {
                    if Prompt.confirm(String(format: L("Удалить список «%@»?"), list.name),
                                      details: String(format: L("Строк в нём: %d. Это не отменить."), list.items.count),
                                      action: L("Удалить")) {
                        store.deleteList(list.id)
                        model.listID = store.lists.first?.id
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(list?.name ?? L("Нет списков")).font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func row(_ idx: Int, _ clip: Clip, total: Int) -> some View {
        ClipRow(badge: idx < 10 ? "\((idx + 1) % 10)" : nil,
                text: ClipText.preview(clip.text),
                subtitle: nil,
                highlighted: idx == model.selection) {
            IconButton(symbol: "pencil", help: L("Изменить")) { begin(.edit(clip.id), text: clip.text) }
        }
        .id(clip.id)
        // The pencil button sits inside the row: one click fires both. Let the button run first and
        // skip the paste if it just started editing, otherwise the panel closes under the edit field.
        .onTapGesture { DispatchQueue.main.async { if model.draft == .none { onPick(clip.text) } } }
        .contextMenu {
            if let listID = list?.id {
                Button(L("Изменить")) { begin(.edit(clip.id), text: clip.text) }
                Button(L("Выше")) { store.move(clip.id, inList: listID, by: -1) }.disabled(idx == 0)
                Button(L("Ниже")) { store.move(clip.id, inList: listID, by: 1) }.disabled(idx == total - 1)
                Divider()
                Button(L("Удалить строку"), role: .destructive) { store.remove(clip.id, fromList: listID) }
            }
        }
    }

    private var draftBar: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: model.draft == .add ? "plus.circle.fill" : "pencil.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .padding(.top, 2)
            TextField(model.draft == .add ? L("Новая строка: ↩ добавить, esc отмена") : L("Текст строки"),
                      text: $model.draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...5)
                .focused($draftFocused)
                .onAppear { DispatchQueue.main.async { draftFocused = true } }
                .onSubmit(commit)
                .onKeyPress(.escape) { cancel(); return .handled }
            Button(model.draft == .add ? L("Добавить") : L("Сохранить"), action: commit)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06))
        .overlay(alignment: .top) { Divider().opacity(0.6) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func begin(_ draft: ListModel.Draft, text: String = "") {
        model.draft = draft
        model.draftText = text
        draftFocused = true
        // A context menu takes focus while it closes; claim it back once it's gone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { draftFocused = true }
    }

    private func commit() {
        let text = model.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch model.draft {
        case .add:
            if let id = list?.id {
                store.addText(text, toList: id)
            } else {
                let id = store.createList(named: L("Мой список"), with: nil)
                store.addText(text, toList: id)
                model.listID = id
            }
            model.draftText = ""
        case .edit(let clipID):
            if let id = list?.id { store.updateText(clipID, inList: id, to: text) }
            cancel()
        case .none:
            break
        }
    }

    private func cancel() {
        model.draft = .none
        model.draftText = ""
        draftFocused = false
    }
}
