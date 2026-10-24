import AppKit

/// A small note near the top of the screen that fades out by itself. Doesn't take focus or clicks.
enum Toast {
    private static var panel: NSPanel?
    private static var hide: DispatchWorkItem?

    static func show(_ text: String, seconds: Double = 2.2) {
        hide?.cancel()
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 36, height: label.frame.height + 20)

        let p = panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.ignoresMouseEvents = true
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.sharingType = .none
            panel = p
            return p
        }()
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        label.frame.origin = NSPoint(x: 18, y: 10)
        effect.addSubview(label)
        p.contentView = effect

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            p.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height - 24, width: size.width, height: size.height), display: true)
        }
        p.alphaValue = 1
        p.orderFrontRegardless()

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 }) { p.orderOut(nil) }
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
