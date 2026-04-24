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
                    Label("Compile", systemImage: "hammer")
                }

            aiPane
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }
        }
        .padding()
        .frame(width: 540, height: 460)
    }

    private var generalPane: some View {
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.displayName).tag(appearance)
                }
            }

            Toggle("Compile on Save", isOn: $settings.autoBuildOnSave)
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

            Picker("TeX Live Year", selection: $settings.toolchainYear) {
                ForEach(TexToolchainYear.allCases, id: \.self) { year in
                    Text(year.displayName).tag(year)
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

    private var aiPane: some View {
        Form {
            Picker("Provider", selection: $settings.llm.provider) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: settings.llm.provider) { _, newValue in
                if settings.llm.model.isEmpty || LLMProvider.allCases.contains(where: { $0.defaultModel == settings.llm.model }) {
                    settings.llm.model = newValue.defaultModel
                }
            }

            TextField("Model", text: $settings.llm.model)
                .textFieldStyle(.roundedBorder)

            SecureField("API Key", text: $settings.llm.apiKey)
                .textFieldStyle(.roundedBorder)

            HStack {
                Stepper(value: $settings.llm.maxTokens, in: 256...8192, step: 256) {
                    Text("Max Tokens: \(settings.llm.maxTokens)")
                }
            }

            Text(providerHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !settings.llm.isConfigured {
                Label("API key is required before the AI Assistant can respond.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var providerHint: String {
        switch settings.llm.provider {
        case .anthropic:
            return "Anthropic API key starts with sk-ant-. Keys are stored locally in app settings."
        case .openai:
            return "OpenAI API key starts with sk-. Keys are stored locally in app settings."
        }
    }

    private static var monospacedFontNames: [String] {
        let preferred = ["Menlo", "Monaco", "SF Mono", "Courier New"]
        let available = Set(NSFontManager.shared.availableFontFamilies)
        let installedPreferred = preferred.filter { available.contains($0) }
        return installedPreferred.isEmpty ? ["Menlo"] : installedPreferred
    }
}
