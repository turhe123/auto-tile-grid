import AppKit
import SwiftUI

/// Shows a brief, click-through label at the centre of a screen that fades after one second.
final class OverlayController {
    static let shared = OverlayController()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    private init() {}

    func show(_ text: String, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        hideWork?.cancel()
        panel?.orderOut(nil)

        let host = NSHostingView(rootView: OverlayLabel(text: text))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let origin = CGPoint(x: (screen.frame.midX - size.width / 2).rounded(),
                             y: (screen.frame.midY - size.height / 2).rounded())
        let p = NSPanel(contentRect: CGRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        p.contentView = host
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p

        let work = DispatchWorkItem { [weak p] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                p?.animator().alphaValue = 0
            }, completionHandler: { p?.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
}

/// The rounded HUD-style label displayed by `OverlayController`.
private struct OverlayLabel: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "square.grid.2x2")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.72)))
            .padding(4)
    }
}
