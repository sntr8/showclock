import SwiftUI

struct ThemeEditorView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var editingTheme: Theme? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach($settings.themes) { $theme in
                    ThemeRowView(theme: $theme, isBuiltIn: theme.isBuiltIn) {
                        settings.save()
                    }
                }
                .onDelete { indices in
                    let deletable = indices.filter { !settings.themes[$0].isBuiltIn }
                    settings.themes.remove(atOffsets: IndexSet(deletable))
                    settings.save()
                }
            }
            .listStyle(.inset)

            Divider()

            Button("Add Theme") {
                let newTheme = Theme(
                    id: UUID(),
                    name: "Custom",
                    isBuiltIn: false,
                    backgroundHex: "#1A1A1A",
                    primaryHex: "#FFFFFF",
                    accentHex: "#AAAAAA"
                )
                settings.themes.append(newTheme)
                settings.save()
            }
            .padding(10)
        }
        .frame(minWidth: 380, minHeight: 300)
    }
}

private struct ThemeRowView: View {
    @Binding var theme: Theme
    let isBuiltIn: Bool
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Name", text: $theme.name)
                .disabled(isBuiltIn)
                .frame(width: 80)

            ColorPickerHex(label: "BG", hex: $theme.backgroundHex, onChange: onChange)
            ColorPickerHex(label: "Text", hex: $theme.primaryHex, onChange: onChange)
            ColorPickerHex(label: "Accent", hex: $theme.accentHex, onChange: onChange)

            // Preview swatch
            HStack(spacing: 2) {
                Rectangle().fill(theme.backgroundColor).frame(width: 20, height: 20)
                Rectangle().fill(theme.primaryColor).frame(width: 20, height: 20)
                Rectangle().fill(theme.accentColor).frame(width: 20, height: 20)
            }
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator, lineWidth: 0.5))

            if isBuiltIn {
                Text("Built-in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: theme.name) { _, _ in if !isBuiltIn { onChange() } }
    }
}

private struct ColorPickerHex: View {
    let label: String
    @Binding var hex: String
    let onChange: () -> Void

    var binding: Binding<Color> {
        Binding(
            get: { Color(hex: hex) ?? .black },
            set: { hex = $0.toHex(); onChange() }
        )
    }

    var body: some View {
        VStack(spacing: 2) {
            ColorPicker("", selection: binding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}
