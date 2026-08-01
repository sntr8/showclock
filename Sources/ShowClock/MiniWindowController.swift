import SwiftUI
import AppKit

// Owns a small floating panel that mirrors the countdown/clock at window
// size instead of full screen, and stays pinned above every other app (not
// just ShowClock) — requested so an operator can keep an eye on remaining
// show time while working in QLab, a browser, etc. alongside it. A
// non-activating NSPanel, not a SwiftUI WindowGroup: WindowGroup windows
// join the normal app window layer and steal focus/activate the app on
// click, which this must never do.
@MainActor
final class MiniWindowController: ObservableObject {
    @Published private(set) var isShowing = false
    private var panel: NSPanel?

    // `onScreen` is where the main Settings window currently is — the first
    // time this opens (nothing saved yet under "MiniClockWindow"), it should
    // land next to what the operator is actually looking at, not wherever
    // AppKit's default placement happens to land a fresh window (which is
    // the primary/menu-bar display, regardless of which screen the operator
    // is working on or which screen the kiosk clock is showing on).
    func show(settings: AppSettings, qlab: QLabManager, onScreen: NSScreen?) {
        guard panel == nil else { return }

        let content = MiniClockView(onClose: { [weak self] in self?.close() })
            .environmentObject(settings)
            .environmentObject(qlab)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 130),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: content)
        // .floating (not .statusBar, as the full kiosk display uses): this
        // needs to sit above ordinary app windows, but doesn't need to cover
        // the menu bar or beat literally everything the way the kiosk
        // display does.
        panel.level = .floating
        // canJoinAllSpaces + fullScreenAuxiliary is what lets it keep
        // following the operator across Spaces and stay visible even over
        // another app that's in full screen — the whole point of "pinned on
        // top of any app".
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 160, height: 80)

        // Remembers position/size across launches; falls back to centering
        // on the Settings window's screen the first time there's nothing
        // saved yet under this name.
        panel.setFrameAutosaveName("MiniClockWindow")
        if !panel.setFrameUsingName("MiniClockWindow") {
            if let onScreen {
                let visible = onScreen.visibleFrame
                let frame = panel.frame
                panel.setFrameOrigin(NSPoint(
                    x: visible.midX - frame.width / 2,
                    y: visible.midY - frame.height / 2
                ))
            } else {
                panel.center()
            }
        }

        panel.orderFront(nil)

        self.panel = panel
        isShowing = true
    }

    func close() {
        panel?.saveFrame(usingName: "MiniClockWindow")
        panel?.orderOut(nil)
        panel = nil
        isShowing = false
    }

    func toggle(settings: AppSettings, qlab: QLabManager, onScreen: NSScreen?) {
        if isShowing {
            close()
        } else {
            show(settings: settings, qlab: qlab, onScreen: onScreen)
        }
    }
}
