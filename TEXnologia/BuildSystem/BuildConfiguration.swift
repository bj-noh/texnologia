import Foundation

enum LatexEngine: String, Codable, CaseIterable, Sendable {
    case pdfLaTeX = "pdflatex"
    case xeLaTeX = "xelatex"
    case luaLaTeX = "lualatex"

    var displayName: String {
        switch self {
        case .pdfLaTeX: return "pdfLaTeX"
        case .xeLaTeX: return "XeLaTeX"
        case .luaLaTeX: return "LuaLaTeX"
        }
    }

    var latexmkFlag: String {
        switch self {
        case .pdfLaTeX: return "-pdf"
        case .xeLaTeX: return "-xelatex"
        case .luaLaTeX: return "-lualatex"
        }
    }
}

enum TexToolchainYear: String, Codable, CaseIterable, Sendable {
    case texLive2024 = "2024"
    case texLive2025 = "2025"

    var displayName: String {
        rawValue
    }
}

struct BuildConfiguration: Codable, Sendable, Equatable {
    var rootFile: URL
    var projectDirectory: URL
    var outputDirectory: URL
    var engine: LatexEngine
    var toolchainYear: TexToolchainYear
    var shellEscape: Bool
    var synctexEnabled: Bool
    var maxDirectPasses: Int

    static func `default`(
        rootFile: URL,
        engine: LatexEngine = .pdfLaTeX,
        toolchainYear: TexToolchainYear = .texLive2024,
        shellEscape: Bool = false
    ) -> BuildConfiguration {
        let projectDirectory = rootFile.deletingLastPathComponent()
        return BuildConfiguration(
            rootFile: rootFile,
            projectDirectory: projectDirectory,
            outputDirectory: projectDirectory.appendingPathComponent(".texnologia-build", isDirectory: true),
            engine: engine,
            toolchainYear: toolchainYear,
            shellEscape: shellEscape,
            synctexEnabled: true,
            maxDirectPasses: 4
        )
    }
}

struct BuildResult: Sendable {
    var succeeded: Bool
    var pdfURL: URL?
    var issues: [BuildIssue]
    var rawLog: String
}
