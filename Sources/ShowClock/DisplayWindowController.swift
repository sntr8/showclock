import SwiftUI
import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

// Borderless windows don't become key by default; without this override the
// window can never receive focus/key events at all.
private final class KioskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// Owns the borderless, always-on-top window that shows the clock full screen
// on the chosen display. A plain NSWindow (not a SwiftUI WindowGroup) so we can
// pin it to an arbitrary NSScreen and sit above the menu bar without an
// animated Spaces transition.
@MainActor
final class DisplayWindowController: ObservableObject {
    @Published private(set) var isShowing = false
    private var window: NSWindow?
    private var escapeMonitor: Any?

    // activate: false is for moving an already-open window to a newly picked
    // display without stealing focus from Settings. It still rebuilds the
    // window rather than just calling setFrame on the old one: with
    // "Displays have separate Spaces" (macOS default), a window is tied to
    // the Space of the display it was created on, and merely repositioning
    // its frame onto another screen doesn't re-associate it with that
    // display's Space — it just gets clipped/hidden. Recreating it fresh on
    // the target screen is what actually relocates it.
    func show(on screen: NSScreen, settings: AppSettings, qlab: QLabManager, activate: Bool = true) {
        close()

        let content = ContentView(onClose: { [weak self] in self?.close() })
            .environmentObject(settings)
            .environmentObject(qlab)

        let window = KioskWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentView = NSHostingView(rootView: content)
        window.setFrame(screen.frame, display: true)
        // .screenSaver sits above literally everything the OS renders,
        // including the Cmd+Tab switcher and Mission Control — it doesn't
        // just fail to help with key routing, it visually hides your only way
        // out. .statusBar is just above the menu bar, which is all we need to
        // cover it, without blocking system UI.
        window.level = .statusBar
        // .canJoinAllSpaces windows are documented to never become key no
        // matter what canBecomeKey returns — almost certainly why Escape
        // wasn't reaching this window's local monitor.
        window.collectionBehavior = [.stationary, .ignoresCycle]
        window.isOpaque = true
        window.hasShadow = false
        // Without this, closing the window (see close() below) can trigger
        // AppKit's default close-transform animation — which, for this
        // particular combination of borderless/.statusBar-level/full-screen
        // window, has been observed to crash during the animation's own
        // dealloc (EXC_BAD_ACCESS inside _NSWindowTransformAnimation
        // dealloc, nothing in our own code on the stack). Not worth
        // animating a full-screen kiosk display closing anyway.
        window.animationBehavior = .none

        if activate {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }

        self.window = window
        isShowing = true

        // A local monitor, not NSWindow.keyDown: the hosted SwiftUI content
        // becomes first responder and would otherwise consume/swallow the key
        // event before it ever bubbles up to the window.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.close()
            return nil
        }
    }

    func close() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        guard let window else { return }
        self.window = nil
        isShowing = false

        // orderOut only, deliberately not window.close(): calling .close()
        // on this specific window (borderless, .statusBar level, SwiftUI-
        // hosted content) reliably crashes deep inside AppKit's own teardown
        // (EXC_BAD_ACCESS during a later autorelease pool drain, zero
        // application frames on the crashing thread — confirmed reproducible
        // across several independent fix attempts that only changed the
        // timing/ordering of the .close() call, never removing it). This
        // does mean the window and its SwiftUI view tree leak on every close
        // or display switch instead of being released — a real but bounded
        // cost, and a far better trade than a crash mid-show.
        window.orderOut(nil)
    }
}
