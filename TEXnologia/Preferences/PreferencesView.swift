import AppKit
import SwiftUI

struct PreferencesView: View {
    @Binding var settings: AppSettings
    @State private var selectedPane: PreferencesPane = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    FolioDocumentMark(size: 27)
                    Text("Preferences")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.bottom, 26)

                ForEach(PreferencesPane.allCases) { pane in
                    Button {
                        selectedPane = pane
                    } label: {
                        Label(pane.title, systemImage: pane.symbol)
                            .font(.system(size: 12, weight: selectedPane == pane ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .foregroundStyle(selectedPane == pane ? FolioTheme.accent : FolioTheme.muted)
                            .background(selectedPane == pane ? FolioTheme.accentSoft : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Make it feel like your space.")
                    .font(.system(size: 10))
                    .foregroundStyle(FolioTheme.muted)
                    .lineSpacing(3)
            }
            .padding(20)
            .frame(width: 190)
            .background(FolioTheme.sidebar)

            FolioTheme.border.frame(width: 1)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedPane.title)
                        .font(.system(size: 24, weight: .semibold))
                    Text(selectedPane.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(FolioTheme.muted)
                }
                .padding(.horizontal, 28)
                .padding(.top, 30)
                .padding(.bottom, 12)

                Group {
                    switch selectedPane {
                    case .general: generalPane
                    case .editor: editorPane
                    case .build: buildPane
                    case .ai: aiPane
                    }
                }
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(FolioTheme.canvas)
        }
        .foregroundStyle(FolioTheme.text)
        .tint(FolioTheme.accent)
        .frame(width: 740, height: 580)
    }

    private var generalPane: some View {
        Form {
            Section("Your workspace") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
            }
            Section("Project workflow") {
                Toggle("Compile after clicking Save", isOn: $settings.autoBuildOnSave)
                Text("⌘S always saves and compiles. ⌘B compiles the current project.")
                    .font(.system(size: 11))
                    .foregroundStyle(FolioTheme.muted)
                Toggle("Hide intermediate files", isOn: $settings.hidesIntermediateArtifacts)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var editorPane: some View {
        Form {
            Section("Writing surface") {
                Picker("Editor theme", selection: $settings.editorTheme) {
                    ForEach(EditorTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }

                Picker("Font", selection: $settings.editorFontName) {
                    ForEach(Self.monospacedFontNames, id: \.self) { fontName in
                        Text(fontName).tag(fontName)
                    }
                }

                LabeledContent("Font size") {
                    HStack {
                        Slider(value: $settings.editorFontSize, in: 10...28, step: 1)
                        Text("\(Int(settings.editorFontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(FolioTheme.muted)
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                LabeledContent("Line spacing") {
                    HStack {
                        Slider(value: $settings.editorLineSpacing, in: 0...12, step: 1)
                        Text("\(Int(settings.editorLineSpacing)) px")
                            .monospacedDigit()
                            .foregroundStyle(FolioTheme.muted)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
            Section("Writing aids") {
                Toggle("Spell checking", isOn: $settings.editorSpellChecking)
                Toggle("Show invisible characters", isOn: $settings.editorShowInvisibles)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var buildPane: some View {
        Form {
            Section("Build your document") {
                Picker("Default TeX engine", selection: $settings.defaultEngine) {
                    ForEach(LatexEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }

                Picker("TeX Live version", selection: $settings.toolchainYear) {
                    ForEach(TexToolchainYear.allCases, id: \.self) { year in
                        Text(year.displayName).tag(year)
                    }
                }
            }
            Section("Advanced") {
                Toggle("Enable shell escape", isOn: $settings.shellEscapeEnabled)
                Text("Allows TeX documents to run external commands during compilation. Disabled by default.")
                    .font(.system(size: 11))
                    .foregroundStyle(FolioTheme.muted)
                    .lineSpacing(3)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var aiPane: some View {
        Form {
            Section("Connection") {
                Picker("Provider", selection: $settings.llm.provider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: settings.llm.provider) { _, newValue in
                    let allKnownDefaults = Set(LLMProvider.allCases.map(\.defaultModel))
                    if settings.llm.model.isEmpty || allKnownDefaults.contains(settings.llm.model) {
                        settings.llm.model = newValue.defaultModel
                    }
                }

                Picker("Suggested model", selection: modelPickerBinding) {
                    ForEach(settings.llm.provider.suggestedModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                    Text("Custom…").tag("__custom__")
                }

                TextField("Model", text: $settings.llm.model)
                    .textFieldStyle(.roundedBorder)

                LabeledContent("API Key") {
                    APIKeyField(text: $settings.llm.apiKey,
                                enabled: settings.llm.provider.requiresAPIKey)
                        .frame(minHeight: 22)
                }
                Text(settings.llm.provider.apiKeyHint)
                    .font(.system(size: 11))
                    .foregroundStyle(FolioTheme.muted)

                if !settings.llm.isConfigured {
                    Label("API key is required before the AI Assistant can respond.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section("Response length") {
                Stepper(value: $settings.llm.maxTokens, in: 256...8192, step: 256) {
                    Text("Maximum tokens: \(settings.llm.maxTokens)")
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var modelPickerBinding: Binding<String> {
        Binding<String>(
            get: {
                let suggested = settings.llm.provider.suggestedModels
                return suggested.contains(settings.llm.model) ? settings.llm.model : "__custom__"
            },
            set: { newValue in
                if newValue != "__custom__" {
                    settings.llm.model = newValue
                }
            }
        )
    }

    private static var monospacedFontNames: [String] {
        let preferred = ["Menlo", "Monaco", "SF Mono", "Courier New"]
        let available = Set(NSFontManager.shared.availableFontFamilies)
        let installedPreferred = preferred.filter { available.contains($0) }
        return installedPreferred.isEmpty ? ["Menlo"] : installedPreferred
    }
}

private enum PreferencesPane: String, CaseIterable, Identifiable {
    case general, editor, build, ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .editor: return "Editor"
        case .build: return "Compile"
        case .ai: return "AI Assistant"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .editor: return "text.cursor"
        case .build: return "play.rectangle"
        case .ai: return "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "A comfortable space for your documents."
        case .editor: return "Fine-tune the way you write and read."
        case .build: return "Turn your source into a finished document."
        case .ai: return "Bring your preferred AI into your project."
        }
    }
}

private struct APIKeyField: NSViewRepresentable {
    @Binding var text: String
    var enabled: Bool

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusingTextField()
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.placeholderString = "sk-..."
        field.stringValue = text
        field.isEditable = true
        field.isSelectable = true
        field.delegate = context.coordinator
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.isEnabled = enabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: APIKeyField
        init(_ parent: APIKeyField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }

    final class FocusingTextField: NSTextField {
        override var acceptsFirstResponder: Bool { isEnabled }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if let window {
                if !window.isKeyWindow {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                window.makeFirstResponder(self)
            }
            super.mouseDown(with: event)
        }
    }
}
