# ShowTimer

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
| ShowTimerApp.swift | App entry. Only scenes are Settings and the theme-editor WindowGroup; an `AppDelegate` closes any auto-opened window at launch and force-shows Settings, so Settings is the only window on launch |
| DisplayWindowController.swift | Owns the borderless kiosk `NSWindow` that shows the clock full screen on the chosen `NSScreen`; opened/closed from Settings, not a SwiftUI `WindowGroup` |
| ContentView.swift | Root view rendered inside the kiosk window; switches ClockView ↔ CountdownView based on showtime |
| ClockView.swift | Pre-show full-screen clock (HH:MM:SS) |
| CountdownView.swift | Post-showtime countdown (HH:MM:SS, supports negative/over-time) |
| AppSettings.swift | ObservableObject; all persisted settings via UserDefaults, incl. `selectedDisplayID` |
| Theme.swift | Theme model + Color↔hex helpers |
| ThemeEditorView.swift | Standalone window for creating/editing/deleting themes |
| SettingsView.swift | The main (only-at-launch) window: OSC config, show times, theme picker, display picker + "Open Clock Display" |
| ScreenArrangementView.swift | Mini diagram of connected displays for picking which screen the clock opens on, with a live miniature clock preview on the selected one |
| QLab/QLabManager.swift | OSC UDP client; polls QLab every 1 s for selected cue |

## Architecture notes

- **No external packages.** OSC is implemented with raw POSIX UDP sockets in QLabManager; OSC message encode/decode is hand-rolled (QLab's subset is simple).
- **QLab reply format.** QLab replies are addressed to `/reply` + the original query path (e.g. `/reply/workspaces`), with a single JSON string argument — not `/reply` with the path and JSON as two arguments. See docs/qlab-osc.md.
- **Launch behavior.** Only the Settings window opens on launch. The clock itself is *not* a SwiftUI `WindowGroup` window — `DisplayWindowController` creates a borderless `NSWindow` pinned to a specific `NSScreen`, above the menu bar level, shown/closed via the "Open/Close Clock Display" button in Settings.
- **Font sizing.** Numbers use `Font.system(...).monospacedDigit()` + `.fontWidth(.compressed)` + `minimumScaleFactor(0.01)`. Font size is set to 82% of window height; SwiftUI scales down to fit width. Compressed width gives a larger rendered height than monospaced.
- **Theme editor** opens as a separate native window (`WindowGroup(id: "theme-editor")`), not a sheet, so it has standard traffic-light buttons.
- **Showtime logic.** Times are stored as HH:MM only; always applied to today's date. If show-end ≤ showtime, end is treated as next day (post-midnight shows).

## See also

- [docs/qlab-osc.md](docs/qlab-osc.md) — QLab OSC API details and connection flow
- [docs/themes.md](docs/themes.md) — Theme model, built-in presets, persistence format
