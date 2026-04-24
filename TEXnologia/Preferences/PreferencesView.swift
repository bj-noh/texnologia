import AppKit
import SwiftUI

struct PreferencesView: View {
    @Binding var settings: AppSettings

    var body: some View {
        TabView {
            generalPane
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            editorPane
                .tabItem {
                    Label("Editor", systemImage: "text.cursor")
                }

            buildPane
                .tabItem {
                    Label("Build", systemImage: "hammer")
                }
        }
        .padding()
        .frame(width: 520, height: 420)
    }

    private var generalPane: some View {
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.displayName).tag(appearance)
                }
            }

            Toggle("Build on Save", isOn: $settings.autoBuildOnSave)
            Toggle("Hide Intermediate Artifacts", isOn: $settings.hidesIntermediateArtifacts)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var editorPane: some View {
        Form {
            Picker("Editor Theme", selection: $settings.editorTheme) {
                ForEach(EditorTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }

            Picker("Font", selection: $settings.editorFontName) {
                ForEach(Self.monospacedFontNames, id: \.self) { fontName in
                    Text(fontName).tag(fontName)
                }
            }

            HStack {
                Slider(value: $settings.editorFontSize, in: 10...28, step: 1)
                Text("\(Int(settings.editorFontSize)) pt")
                    .frame(width: 48, alignment: .trailing)
            }

            HStack {
                Slider(value: $settings.editorLineSpacing, in: 0...12, step: 1)
                Text("\(Int(settings.editorLineSpacing)) px")
                    .frame(width: 48, alignment: .trailing)
            }

            Toggle("Spell Checking", isOn: $settings.editorSpellChecking)
            Toggle("Show Invisible Characters", isOn: $settings.editorShowInvisibles)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var buildPane: some View {
        Form {
            Picker("Default TeX Engine", selection: $settings.defaultEngine) {
                ForEach(LatexEngine.allCases, id: \.self) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }

            Toggle("Enable Shell Escape", isOn: $settings.shellEscapeEnabled)
            Text("Shell escape is disabled by default because TeX documents can execute external commands when it is enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private static var monospacedFontNames: [String] {
        let preferred = ["Menlo", "Monaco", "SF Mono", "Courier New"]
        let available = Set(NSFontManager.shared.availableFontFamilies)
        let installedPreferred = preferred.filter { available.contains($0) }
        return installedPreferred.isEmpty ? ["Menlo"] : installedPreferred
    }
}
