# Themes

## Model

Each theme has: `id` (UUID), `name`, `isBuiltIn` flag, and three hex color strings: `backgroundHex`, `primaryHex`, `accentHex`.

- **primary** — main time digits
- **accent** — secondary text ("Next:", "Show at", dim colors when over time)

Colors are stored as `#RRGGBB` hex strings and converted to SwiftUI `Color` on demand.

## Built-in presets

| Name  | Background | Primary | Accent  |
|-------|-----------|---------|---------|
| Day   | #FFFFFF   | #000000 | #555555 |
| Night | #000000   | #CC0000 | #880000 |

Built-in themes cannot be deleted or renamed. They are always prepended to the list on load.

## Persistence

Themes are stored in `UserDefaults` under the key `"themes"` as a JSON-encoded `[Theme]` array. On load, built-in themes are always re-created from code and merged with any saved custom themes — so built-in colors cannot drift.

`selectedThemeID` is stored as a UUID string under `"selectedThemeID"`.

## Quick-switch shortcuts

Cmd+1, Cmd+2, Cmd+3 … cycle through themes in list order (registered in the app menu via `CommandGroup`).
