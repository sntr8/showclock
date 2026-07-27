import SwiftUI

struct ThemeEditorView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

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
                Button("Add Theme") {
                    settings.themes.append(Theme(
                        id: UUID(),
                        name: "Custom",
                        isBuiltIn: false,
                        backgroundHex: "#1A1A1A",
                        primaryHex: "#FFFFFF",
                        accentHex: "#AAAAAA"
                    ))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 460, minHeight: 320)
        .onChange(of: settings.themes) { _, _ in settings.save() }
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

            ColorPickerHex(label: "BG",     hex: $theme.backgroundHex)
            ColorPickerHex(label: "Text",   hex: $theme.primaryHex)
            ColorPickerHex(label: "Accent", hex: $theme.accentHex)

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
