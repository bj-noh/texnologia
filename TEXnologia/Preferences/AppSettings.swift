import Foundation

struct AppSettings: Codable, Equatable {
    var defaultEngine: LatexEngine
    var toolchainYear: TexToolchainYear
    var shellEscapeEnabled: Bool
    var hidesIntermediateArtifacts: Bool
    var autoBuildOnSave: Bool
    var appearance: AppAppearance
    var editorTheme: EditorTheme
    var editorFontName: String
    var editorFontSize: Double
    var editorLineSpacing: Double
    var editorWrapLines: Bool
    var editorSpellChecking: Bool
    var editorShowInvisibles: Bool
    var llm: LLMConfiguration

    static let `default` = AppSettings(
        defaultEngine: .pdfLaTeX,
        toolchainYear: .texLive2024,
        shellEscapeEnabled: false,
        hidesIntermediateArtifacts: true,
        autoBuildOnSave: true,
        appearance: .system,
        editorTheme: .system,
        editorFontName: "Menlo",
        editorFontSize: 14,
        editorLineSpacing: 3,
        editorWrapLines: true,
        editorSpellChecking: true,
        editorShowInvisibles: false,
        llm: .default
    )

    init(
        defaultEngine: LatexEngine,
        toolchainYear: TexToolchainYear,
        shellEscapeEnabled: Bool,
        hidesIntermediateArtifacts: Bool,
        autoBuildOnSave: Bool,
        appearance: AppAppearance,
        editorTheme: EditorTheme,
        editorFontName: String,
        editorFontSize: Double,
        editorLineSpacing: Double,
        editorWrapLines: Bool,
        editorSpellChecking: Bool,
        editorShowInvisibles: Bool,
        llm: LLMConfiguration
    ) {
        self.defaultEngine = defaultEngine
        self.toolchainYear = toolchainYear
        self.shellEscapeEnabled = shellEscapeEnabled
        self.hidesIntermediateArtifacts = hidesIntermediateArtifacts
        self.autoBuildOnSave = autoBuildOnSave
        self.appearance = appearance
        self.editorTheme = editorTheme
        self.editorFontName = editorFontName
        self.editorFontSize = editorFontSize
        self.editorLineSpacing = editorLineSpacing
        self.editorWrapLines = editorWrapLines
        self.editorSpellChecking = editorSpellChecking
        self.editorShowInvisibles = editorShowInvisibles
        self.llm = llm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultEngine = try c.decode(LatexEngine.self, forKey: .defaultEngine)
        toolchainYear = try c.decodeIfPresent(TexToolchainYear.self, forKey: .toolchainYear) ?? AppSettings.default.toolchainYear
        shellEscapeEnabled = try c.decode(Bool.self, forKey: .shellEscapeEnabled)
        hidesIntermediateArtifacts = try c.decode(Bool.self, forKey: .hidesIntermediateArtifacts)
        autoBuildOnSave = try c.decode(Bool.self, forKey: .autoBuildOnSave)
        appearance = try c.decode(AppAppearance.self, forKey: .appearance)
        editorTheme = try c.decode(EditorTheme.self, forKey: .editorTheme)
        editorFontName = try c.decode(String.self, forKey: .editorFontName)
        editorFontSize = try c.decode(Double.self, forKey: .editorFontSize)
        editorLineSpacing = try c.decode(Double.self, forKey: .editorLineSpacing)
        editorWrapLines = try c.decode(Bool.self, forKey: .editorWrapLines)
        editorSpellChecking = try c.decode(Bool.self, forKey: .editorSpellChecking)
        editorShowInvisibles = try c.decode(Bool.self, forKey: .editorShowInvisibles)
        llm = try c.decodeIfPresent(LLMConfiguration.self, forKey: .llm) ?? .default
    }
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum EditorTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case paper
    case dusk
    case midnight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .paper: return "Paper"
        case .dusk: return "Dusk"
        case .midnight: return "Midnight"
        }
    }
}
