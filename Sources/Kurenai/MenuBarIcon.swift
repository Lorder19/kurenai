import AppKit

/// The menu bar icon: 紅 (kurenai) as a one-color template image,
/// so macOS tints it for light and dark menu bars like any system icon.
enum MenuBarIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let font = NSFont(name: "HiraginoSans-W6", size: 100) ?? .systemFont(ofSize: 100, weight: .bold)
            var char: UniChar = 0x7D05, glyph: CGGlyph = 0
            guard CTFontGetGlyphsForCharacters(font, &char, &glyph, 1),
                  let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return false }
            // Fit the glyph's ink, not its em box, so it fills the slot like other menu bar icons.
            let ink = path.boundingBoxOfPath
            let scale = rect.height * 0.92 / max(ink.width, ink.height)
            var t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -ink.midX, y: -ink.midY)
            guard let fitted = path.copy(using: &t), let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(fitted)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Kurenai"
        return image
    }
}
