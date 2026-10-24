import AppKit
import SwiftUI

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Floating, non-activating panel: the app you're pasting into stays frontmost.
/// Position and size are remembered per panel name.
final class FloatingPanel: NSPanel {
    private let takesKey: Bool
    private let closesOnResign: Bool
    private var hasFrame = false

    init<Content: View>(name: String, size: NSSize, minSize: NSSize,
                        takesKey: Bool, closesOnResign: Bool, content: Content) {
        self.takesKey = takesKey
        self.closesOnResign = closesOnResign
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        // Clipboard contents must not leak into screen recordings, screenshots or Zoom/Meet shares.
        sharingType = Demo.isOn ? .readOnly : .none
        self.minSize = minSize
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(b)?.isHidden = true
        }

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        // The hidden titlebar still reserves a safe-area strip; let content run to the top edge.
        let host = FirstMouseHostingView(rootView: content.ignoresSafeArea())
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        contentView = effect

        hasFrame = setFrameUsingName(name)
        if !Demo.isOn { setFrameAutosaveName(name) } // screenshot mode must not move your saved windows
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var canBecomeKey: Bool { takesKey }
    override var canBecomeMain: Bool { false }

    // Stray keys in a panel shouldn't beep; real errors beep explicitly.
    override func noResponder(for eventSelector: Selector) {
        if eventSelector == #selector(NSResponder.keyDown(with:)) { return }
        super.noResponder(for: eventSelector)
    }

    override func resignKey() {
        super.resignKey()
        if closesOnResign && !Demo.isOn { orderOut(nil) } // demo panels stay put for screenshots
    }

    func present() {
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if !hasFrame || !onScreen {
            centerOnMouseScreen()
            hasFrame = true
        }
        if takesKey { makeKeyAndOrderFront(nil) } else { orderFrontRegardless() }
    }

    private func centerOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY - frame.height / 2 + f.height * 0.1))
    }
}
