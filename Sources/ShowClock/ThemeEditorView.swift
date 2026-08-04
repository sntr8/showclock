import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ThemeEditorView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showImportError = false
    @State private var importErrorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach($settings.themes) { $theme in
                    ThemeRowView(theme: $theme) {
                        settings.themes.removeAll { $0.id == theme.id }
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                // A split control, not two separate buttons: clicking "+"
                // adds a theme directly; only the chevron opens the menu.
                Menu {
                    Button("Export Custom Themes...") { exportThemes() }
                        .disabled(!settings.themes.contains { !$0.isBuiltIn })
                    Button("Import Themes...") { importThemes() }
                } label: {
                    Image(systemName: "plus")
                } primaryAction: {
                    settings.themes.append(Theme(
                        id: UUID(),
                        name: "Custom",
                        isBuiltIn: false,
                        backgroundHex: "#1A1A1A",
                        primaryHex: "#FFFFFF",
                        accentHex: "#AAAAAA"
                    ))
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Add Theme, or Export/Import from the menu")

                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        // 460 was enough for "BG/Text/Accent"-width colour columns; the
        // plain-language labels need more, and below this the row's trailing
        // "Built-in" / delete control gets clipped off the right edge.
        .frame(minWidth: 540, minHeight: 320)
        .onChange(of: settings.themes) { _, _ in settings.save() }
        .alert("Couldn't Import Themes", isPresented: $showImportError) {
            Button("OK") {}
        } message: {
            Text(importErrorMessage)
        }
    }

    private func exportThemes() {
        let custom = settings.themes.filter { !$0.isBuiltIn }
        guard !custom.isEmpty, let data = try? JSONEncoder().encode(custom) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ShowClock Themes.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    private func importThemes() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let data = try? Data(contentsOf: url) else {
            importErrorMessage = "Couldn't read that file."
            showImportError = true
            return
        }
        // Accept either a full export (an array) or a single theme, so a
        // hand-edited or individually-shared theme file still works.
        let imported: [Theme]
        if let array = try? JSONDecoder().decode([Theme].self, from: data) {
            imported = array
        } else if let single = try? JSONDecoder().decode(Theme.self, from: data) {
            imported = [single]
        } else {
            importErrorMessage = "That file doesn't look like a ShowClock theme export."
            showImportError = true
            return
        }
        // Fresh IDs and forced isBuiltIn = false: an imported file claiming
        // to be a built-in, or reusing an existing theme's ID, shouldn't be
        // able to collide with or overwrite what's already here.
        for theme in imported {
            settings.themes.append(Theme(
                id: UUID(),
                name: theme.name,
                isBuiltIn: false,
                backgroundHex: theme.backgroundHex,
                primaryHex: theme.primaryHex,
                accentHex: theme.accentHex
            ))
        }
    }
}

private struct ThemeRowView: View {
    @Binding var theme: Theme
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Name", text: $theme.name)
                .disabled(theme.isBuiltIn)
                .frame(width: 90)

            // Named for what each one paints on the display, rather than
            // "BG/Text/Accent": "Accent" in particular gave no clue that it
            // controls the current time, the Next: cue line and the mini
            // window's remaining line, which made a first theme a guessing game.
            ColorPickerHex(label: "Background", hex: $theme.backgroundHex)
            ColorPickerHex(label: "Clock",      hex: $theme.primaryHex)
            ColorPickerHex(label: "Details",    hex: $theme.accentHex)

            // Preview swatch
            HStack(spacing: 2) {
                Rectangle().fill(theme.backgroundColor).frame(width: 20, height: 20)
                Rectangle().fill(theme.primaryColor).frame(width: 20, height: 20)
                Rectangle().fill(theme.accentColor).frame(width: 20, height: 20)
            }
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator, lineWidth: 0.5))

            Spacer()

            if theme.isBuiltIn {
                Text("Built-in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .center)
            } else {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .frame(width: 50, alignment: .center)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ColorPickerHex: View {
    let label: String
    @Binding var hex: String

    var binding: Binding<Color> {
        Binding(
            get: { Color(hex: hex) ?? .black },
            set: { hex = $0.toHex() }
        )
    }

    var body: some View {
        // Fixed column width, with the well sized to what AppKit actually
        // draws. A macOS ColorPicker's intrinsic width is wider than the
        // 28pt frame this used to impose, and it paints past that frame
        // rather than clipping to it — so once the labels grew from
        // "BG/Text/Accent" to "Background/Clock/Details" and widened the
        // columns, neighbouring wells visibly overlapped each other.
        VStack(spacing: 2) {
            ColorPicker("", selection: binding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44, height: 24)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 68)
    }
}
