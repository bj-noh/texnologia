import Foundation

struct AppSettings: Codable, Equatable {
    var defaultEngine: LatexEngine
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

    static let `default` = AppSettings(
        defaultEngine: .pdfLaTeX,
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
        editorShowInvisibles: false
    )
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
