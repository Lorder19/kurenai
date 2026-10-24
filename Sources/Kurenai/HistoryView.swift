import AppKit
import SwiftUI

final class HistoryModel: ObservableObject {
    @Published var query = ""
    @Published var tab: UUID?
    @Published var selection = 0
    @Published var focusToken = 0

    func items(in store: Store) -> [Clip] {
        var source = store.history
        if let id = tab, let list = store.lists.first(where: { $0.id == id }) { source = list.items }
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? source : source.filter {
            $0.image == nil ? $0.text.localizedCaseInsensitiveContains(q) : (L("Картинка") + " картинка image 图片").localizedCaseInsensitiveContains(q)
        }
    }
}

struct HistoryView: View {
    @ObservedObject var store: Store
    @ObservedObject var model: HistoryModel
    let onPick: (Clip) -> Void
    let onClose: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = model.items(in: store)
        VStack(spacing: 0) {
            PanelHeader(icon: "clock.arrow.circlepath") {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Поиск по буферу"), text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($searchFocused)
                        .onKeyPress(.downArrow) { move(1, current.count); return .handled }
                        .onKeyPress(.upArrow) { move(-1, current.count); return .handled }
                        .onKeyPress(.tab) { cycleTab(); return .handled }
                        .onKeyPress(.escape) { onClose(); return .handled }
                        .onKeyPress(phases: .down) { press in
                            guard press.modifiers == .command, let n = Self.digit(press.key), n >= 1 else { return .ignored }
                            let list = current
                            if list.indices.contains(n - 1) { onPick(list[n - 1]) }
                            return .handled
                        }
                        .onSubmit {
                            let list = current
                            if list.indices.contains(model.selection) { onPick(list[model.selection]) }
                        }
                }
            } trailing: {
                Text("\(items.count)")
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(L("История"), id: nil)
                    ForEach(store.lists) { chip($0.name, id: $0.id) }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 8)

            Divider().opacity(0.6)

            if items.isEmpty {
                EmptyState(icon: model.query.isEmpty ? "tray" : "magnifyingglass",
                           title: model.query.isEmpty ? L("Пусто") : L("Ничего не найдено"),
                           subtitle: model.query.isEmpty ? L("Всё, что скопируешь, появится здесь") : L("Попробуй другой запрос"))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, clip in
                                ClipRow(badge: idx < 9 ? "\(idx + 1)" : nil,
                                        text: clip.image == nil ? ClipText.preview(clip.text) : ClipText.imageTitle(clip),
                                        thumbnail: clip.image.flatMap(ImageStore.thumbnail),
                                        subtitle: ClipText.subtitle(for: clip),
                                        highlighted: idx == model.selection)
                                    .id(clip.id)
                                    .onTapGesture { onPick(clip) }
                                    .contextMenu { menu(for: clip) }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: model.selection) { _, new in
                        if items.indices.contains(new) { proxy.scrollTo(items[new].id) }
                    }
                }
            }

            HintBar(hints: [("↩", L("вставить")), ("⌘1–9", L("быстро")), ("⇥", L("вкладка")), ("esc", L("закрыть"))])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { searchFocused = true }
        .onChange(of: model.query) { model.selection = 0 }
        .onChange(of: model.tab) { model.selection = 0 }
    }

    /// The list as it is right now. Key handlers must not use the `items` captured at the last render:
    /// while the panel was hidden new copies may have arrived, and Return would pick by a stale list.
    private var current: [Clip] { model.items(in: store) }

    private static func digit(_ key: KeyEquivalent) -> Int? {
        Int(String(key.character))
    }

    private func chip(_ title: String, id: UUID?) -> some View {
        let on = model.tab == id
        return Button { model.tab = id } label: {
            Text(title)
                .font(.system(size: 12, weight: on ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menu(for clip: Clip) -> some View {
        if let listID = model.tab {
            Button(L("Убрать из списка")) { store.remove(clip.id, fromList: listID) }
        } else {
            if clip.image == nil { Menu(L("Добавить в список")) {
                ForEach(store.lists) { list in
                    Button(list.name) { store.add(clip, toList: list.id) }
                }
                Divider()
                Button(L("Новый список…")) {
                    if let name = Prompt.text(title: L("Новый список")) { store.createList(named: name, with: clip) }
                }
            } }
            Button(L("Удалить из истории"), role: .destructive) { store.deleteFromHistory(clip.id) }
        }
    }

    private func move(_ delta: Int, _ count: Int) {
        guard count > 0 else { return }
        model.selection = max(0, min(count - 1, model.selection + delta))
    }

    private func cycleTab() {
        let all: [UUID?] = [nil] + store.lists.map { Optional($0.id) }
        let i = all.firstIndex(of: model.tab) ?? 0
        model.tab = all[(i + 1) % all.count]
    }
}

/// Modal prompts activate Kurenai; hiding afterwards hands focus back to the app you were working in.
enum Prompt {
    static func text(title: String, initial: String = "") -> String? {
        NSApp.activate()
        defer { NSApp.hide(nil) }
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: L("Отмена"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func confirm(_ title: String, details: String, action: String) -> Bool {
        NSApp.activate()
        defer { NSApp.hide(nil) }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = details
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: L("Отмена"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
