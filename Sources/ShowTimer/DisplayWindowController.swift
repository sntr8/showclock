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

    func show(on screen: NSScreen, settings: AppSettings, qlab: QLabManager) {
        close()

        let content = ContentView()
            .environmentObject(settings)
            .environmentObject(qlab)
            .environmentObject(self)

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

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

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
        window?.orderOut(nil)
        window = nil
        isShowing = false
    }
}
