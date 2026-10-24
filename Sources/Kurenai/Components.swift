import AppKit
import SwiftUI

enum ClipText {
    static func preview(_ s: String) -> String {
        let head = s.prefix(2000)
        let first = head.split(whereSeparator: \.isNewline).first.map(String.init) ?? String(head)
        return String(first.trimmingCharacters(in: .whitespaces).prefix(200))
    }

    static func lineCount(_ s: String) -> Int {
        s.split(whereSeparator: \.isNewline).count
    }

    /// Splits a copied column/block into queue items: one per non-empty line.
    static func lines(_ s: String) -> [String] {
        s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        // Follow the UI language Kurenai actually shows, not a hard-coded one.
        f.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()

    static func ago(_ date: Date) -> String {
        let sec = Int(Date().timeIntervalSince(date))
        switch sec {
        case ..<60: return L("только что")
        case ..<3600: return String(format: L("%d мин назад"), sec / 60)
        case ..<86_400: return String(format: L("%d ч назад"), sec / 3600)
        case ..<172_800: return L("вчера")
        default: return dayMonth.string(from: date)
        }
    }

    /// One line, short enough for a menu.
    static func menuTitle(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.count > 42 ? String(line.prefix(41)) + "…" : line
    }

    static func imageTitle(_ clip: Clip) -> String {
        guard let name = clip.image, let size = ImageStore.size(name) else { return L("Картинка") }
        return String(format: L("Картинка %d×%d"), Int(size.width), Int(size.height))
    }

    static func subtitle(for clip: Clip) -> String {
        let ago = ago(clip.date)
        let n = lineCount(clip.text)
        return n > 1 ? "\(lineCount(label: n)) · \(ago)" : ago
    }

    /// Russian needs three plural forms (строка/строки/строк), the other languages take one format string.
    static func lineCount(label n: Int) -> String {
        if Bundle.main.preferredLocalizations.first == "ru" { return "\(n) \(plural(n, "строка", "строки", "строк"))" }
        return String(format: L("%d строк"), n)
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return one }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
        return many
    }
}

struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct PanelHeader<Title: View, Trailing: View>: View {
    let icon: String
    @ViewBuilder var title: () -> Title
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.14)))
            title()
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(WindowDragArea())
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.accentColor))
            .contentTransition(.numericText())
    }
}

struct ClipRow<Accessory: View>: View {
    let badge: String?
    let text: String
    let thumbnail: NSImage?
    let subtitle: String?
    let highlighted: Bool
    let accessory: Accessory
    @State private var hovering = false

    init(badge: String?, text: String, thumbnail: NSImage? = nil, subtitle: String?, highlighted: Bool = false,
         @ViewBuilder accessory: () -> Accessory) {
        self.badge = badge
        self.text = text
        self.thumbnail = thumbnail
        self.subtitle = subtitle
        self.highlighted = highlighted
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 10) {
            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(highlighted ? Color.white : Color.secondary)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(highlighted ? Color.accentColor : Color.primary.opacity(0.07)))
            }
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if hovering { accessory }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, subtitle == nil ? 6 : 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(highlighted ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hovering ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

extension ClipRow where Accessory == EmptyView {
    init(badge: String?, text: String, thumbnail: NSImage? = nil, subtitle: String?, highlighted: Bool = false) {
        self.init(badge: badge, text: text, thumbnail: thumbnail, subtitle: subtitle, highlighted: highlighted) { EmptyView() }
    }
}

struct KeyCap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
    }
}

struct HintBar: View {
    let hints: [(String, String)]
    var body: some View {
        HStack(spacing: 14) {
            ForEach(hints.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    KeyCap(key: hints[i].0)
                    Text(hints[i].1)
                }
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.system(size: 13, weight: .medium))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// UI strings are written in Russian and used as keys; en.lproj / zh-Hans.lproj hold the translations.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
