# ShowClock

macOS show clock app for live events. Displays a full-screen clock before showtime, then a countdown to show end. Pulls next-cue info from QLab via OSC.

## Build & run

```
swift build
swift run
```

No external dependencies. macOS 14+, Swift 5.9+.

## Key files

| File | Role |
|------|------|
| ShowClockApp.swift | App entry. The Settings WindowGroup is declared first, so it's the one macOS auto-opens at launch; the theme-editor WindowGroup only opens via `openWindow(id:)` |
| DisplayWindowController.swift | Owns the borderless kiosk `NSWindow` that shows the clock full screen on the chosen `NSScreen`; opened/closed/moved from Settings, not a SwiftUI `WindowGroup` |
| ContentView.swift | Root view rendered inside the kiosk window; picks plain clock vs. countdown/overtime via `AppSettings.isShowingPlainClock` (see Architecture notes) |
| ClockView.swift | Full-screen plain clock (HH:MM:SS) — pre-show, no-end-time, and post-overtime states all render this. Shows "Show at HH:MM" only while pre-show, and cue info ("Next: X") only otherwise — the no-end-time mode has nowhere else to show cue info, since CountdownView never renders there |
| CountdownView.swift | Show-window countdown (`-HH:MM:SS`) and overtime (`+HH:MM:SS`, flashing) |
| QRCodeView.swift | Renders a string as a QR code via Core Image's built-in `CIQRCodeGenerator` (no external dependency). Shown top-left in `ContentView`, linking to the GitHub releases page, sized proportionally to screen size (clamped) rather than a fixed pixel size |
| AppSettings.swift | ObservableObject; all persisted settings via UserDefaults, incl. `selectedDisplayID`, `showEndEnabled`, `autoOpenClockOnLaunch` |
| Theme.swift | Theme model + Color↔hex helpers |
| ThemeEditorView.swift | Standalone window for creating/editing/deleting themes |
| SettingsView.swift | The main (only-at-launch) window: OSC config, show times, theme picker, display picker + "Open Clock Display" |
| ScreenArrangementView.swift | Mini diagram of connected displays for picking which screen the clock opens on. The selected display shows a live preview that mirrors ContentView's actual current phase (clock or countdown/overtime), not just always a clock. Each display is a `Button`, not a bare `.onTapGesture` — see Architecture notes |
| QLab/QLabManager.swift | OSC UDP client; polls QLab every 1 s for the selected cue, `runningOrPausedCues` (drives `hasActiveCues`, used to end overtime early), and the full cue list + per-cue `type`/`duration`/`armed`/`actionElapsed`/`continueMode`/parent `mode` (drives `totalRemainingSeconds` — the whole rest-of-show estimate, shown only in Settings; see docs/qlab-osc.md for the non-obvious "where does the sum start" logic and how cues that start together — Timeline Groups or auto-continue chains, QLab's two ways to build "multiple tracks, one cue" — are counted once instead of per track) |

## Architecture notes

- **No external packages.** OSC is implemented with raw POSIX UDP sockets in QLabManager; OSC message encode/decode is hand-rolled (QLab's subset is simple).
- **QLab reply format.** QLab replies are addressed to `/reply` + the original query path (e.g. `/reply/workspaces`), with a single JSON string argument — not `/reply` with the path and JSON as two arguments. See docs/qlab-osc.md.
- **Launch behavior.** Only the Settings window opens on launch. The clock itself is *not* a SwiftUI `WindowGroup` window — `DisplayWindowController` creates a borderless `NSWindow` pinned to a specific `NSScreen`, above the menu bar level, shown/closed via the "Open/Close Clock Display" button in Settings.
- **Display switching.** Picking a different display in Settings while the clock is already open calls `show(activate: false)`, not a plain `setFrame` move: with "Displays have separate Spaces" (macOS default), a window is tied to the Space of the display it was created on, so it has to be rebuilt fresh on the new screen to actually relocate — `activate: false` skips the app-activation/key-window steps so Settings doesn't lose focus in the process.
- **Font sizing.** Numbers use `Font.system(...).monospacedDigit()` + `.fontWidth(.compressed)` + `minimumScaleFactor(0.01)`. Compressed width gives a larger rendered height than monospaced. The big countdown number is 70% of window height in CountdownView (82% in ClockView, which has less competing text); the two info lines are 12%/9% respectively — sized so nothing overflows the fixed-height layout.
- **Theme editor** opens as a separate native window (`WindowGroup(id: "theme-editor")`), not a sheet, so it has standard traffic-light buttons.
- **Showtime logic.** Times are stored as HH:MM only; always applied to today's date. If show-end ≤ showtime, end is treated as next day (post-midnight shows).
- **Optional end time / overtime revert.** `AppSettings.isShowingPlainClock(at:qlab:)` is the single source of truth for clock-vs-countdown, shared by both ContentView (the real display) and ScreenArrangementView's live preview, so they can never disagree. If `showEndEnabled` is off, it's always true — there's nothing to count down to. If it's on: plain clock (pre-show) → countdown (`-HH:MM:SS`) → overtime (`+HH:MM:SS`, flashing) → plain clock again, once QLab's `totalRemainingSeconds` reaches zero. No fixed timeout and no session-local "sticky" flag needed — once the whole-show remaining estimate hits zero it naturally stays there (nothing spontaneously adds more cues), so it's safe to recompute this from scratch every tick. Without a QLab connection there's no way to know the show is over, so overtime just keeps running rather than guessing.
- **ClockView's "Show at" label** only appears when genuinely pre-show (`now < showtimeDate`) — not in the no-end-time-but-past-showtime case, and not after reverting from overtime, both of which also render ClockView.
- **QLab disconnect detection.** UDP has no disconnect signal, so quitting QLab looked identical to a working connection until `QLabManager` started tracking `lastReplyAt` (updated on any parsed message) and checking it every poll tick — no reply for 5s while `isConnected` flips it to false ("Connection lost"), and the same tick's existing "no workspace → resend `/workspaces`" logic then keeps retrying, so a relaunched QLab is picked back up automatically. The 1-second poll timer itself now starts immediately in `start()` (not only after a successful connect) for the same reason: the very first `/workspaces` send used to be a single UDP packet with no retry if lost, which could leave the app stuck on "Connecting..." until a manual Connect click sent a fresh one.
- **Settings' Connect button** hides itself once connected — but only while the live host/port/passcode fields still match what was actually used for that connection (`SettingsView` snapshots them via `.onChange(of: qlab.isConnected)` the moment it succeeds). It reappears if the connection drops or if those fields are edited afterward.
- **`ShowRemainingView` is a separate view, not inlined in `SettingsView`.** `qlab.totalRemainingSeconds` ticks roughly every second while connected (driven by the live poll cycle) — reading it directly in `SettingsView.body` would force the whole Form to re-render on that cadence. Reasonable to keep isolated regardless, but this was *not* the fix for the "can't type in the QLab fields" bug below — that was a real, separate cause.
- **App activation on launch.** Launching via `swift run` (or any unbundled executable) never made the app the frontmost/active one on its own — its window was visible and clickable (clicks can land on a background app's controls), but actual keyboard input kept going to whatever *was* active, e.g. the terminal that launched it, since typing requires the app itself to be active, not just its window to be on top. This is what "can't type into the QLab host/port/passcode fields" actually was (a red herring about Form re-renders was tried and ruled out first). `DisplayWindowController` already called `NSApp.activate` for the kiosk window; `SettingsView.onAppear` now does the same (`setActivationPolicy(.regular)` + `activate(ignoringOtherApps: true)`) for the main window, which is the one that actually needs keyboard input. Verified via `NSWorkspace.shared.frontmostApplication` before/after launch.
- **Multiple tracks under one cue.** `totalRemainingSeconds` used to sum every leaf cue's own `duration` independently, so a "cue" really made of several simultaneous tracks (e.g. stereo stems) was counted once per track instead of once for the whole cue, inflating the estimate. QLab has two distinct, both commonly used, ways to build such a cue — a Group in "Timeline" mode (all children start together) or a flat chain of sibling cues each wired with `continueMode` Auto-continue (no Group at all) — and the first fix here only covered Timeline groups, which didn't fix it for a real show (still reported ~3x the actual length). Now both are detected: each leaf's containing Group's `mode` (`/cue_id/{id}/mode`) and each leaf's own `continueMode` (`/cue_id/{id}/continueMode`) are fetched and cached forever like `type`/`duration`, and `recomputeTotalRemaining` merges consecutive leaves that start together (via either mechanism) into one cluster worth only its longest track's remaining time. See docs/qlab-osc.md.

## See also

- [docs/qlab-osc.md](docs/qlab-osc.md) — QLab OSC API details and connection flow
- [docs/themes.md](docs/themes.md) — Theme model, built-in presets, persistence format
