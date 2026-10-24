import SwiftUI

struct QueueView: View {
    @ObservedObject var queue: PasteQueue
    let onHide: () -> Void

    private var usedCount: Int { min(queue.cursor, queue.items.count) }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(icon: "square.stack.3d.down.right") {
                HStack(spacing: 7) {
                    Text("Paste Queue").font(.system(size: 13, weight: .semibold))
                    if !queue.items.isEmpty {
                        Text("\(usedCount)/\(queue.items.count)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(Color.accentColor))
                            .contentTransition(.numericText())
                    }
                }
            } trailing: {
                if !queue.items.isEmpty {
                    IconButton(symbol: "trash", help: L("Очистить очередь (⇧⌘X)")) { queue.clear() }
                }
                IconButton(symbol: "xmark", help: L("Скрыть, строки сохранятся (⌘')"), action: onHide)
            }

            Divider().opacity(0.6)

            if queue.items.isEmpty {
                EmptyState(icon: "doc.on.doc",
                           title: L("Копируй, и всё встанет в очередь"),
                           subtitle: L("⌘C по одному\n⇧⌘C столбец, каждая строка отдельно"))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(queue.items.enumerated()), id: \.element.id) { idx, item in
                                row(idx, item)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: queue.cursor) { _, new in
                        if queue.items.indices.contains(new) {
                            withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(queue.items[new].id, anchor: .center) }
                        }
                    }
                }
            }

            HintBar(hints: [("⌘V", L("следующая")), ("⇧⌘X", L("очистить")), ("⌘'", L("скрыть"))])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.2), value: queue.items)
        .animation(.snappy(duration: 0.15), value: queue.cursor)
    }

    private func row(_ idx: Int, _ item: QueueItem) -> some View {
        let isNext = idx == queue.cursor
        let used = queue.isUsed(idx)
        return ClipRow(badge: used ? "✓" : "\(idx + 1)",
                       text: ClipText.preview(item.text),
                       subtitle: nil,
                       highlighted: isNext) {
            IconButton(symbol: "xmark", help: L("Убрать из очереди")) { queue.remove(item.id) }
        }
        .opacity(used ? 0.4 : 1)
        .saturation(used ? 0 : 1)
        .id(item.id)
        .onTapGesture { queue.setNext(item.id) }
        .help(L("Нажмите, чтобы эта строка вставилась следующей"))
    }
}
