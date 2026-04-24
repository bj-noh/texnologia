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

struct BuildConfiguration: Codable, Sendable, Equatable {
    var rootFile: URL
    var projectDirectory: URL
    var outputDirectory: URL
    var engine: LatexEngine
    var shellEscape: Bool
    var synctexEnabled: Bool
    var maxDirectPasses: Int

    static func `default`(
        rootFile: URL,
        engine: LatexEngine = .pdfLaTeX,
        shellEscape: Bool = false
    ) -> BuildConfiguration {
        let projectDirectory = rootFile.deletingLastPathComponent()
        return BuildConfiguration(
            rootFile: rootFile,
            projectDirectory: projectDirectory,
            outputDirectory: projectDirectory.appendingPathComponent(".texnologia-build", isDirectory: true),
            engine: engine,
            shellEscape: shellEscape,
            synctexEnabled: true,
            maxDirectPasses: 3
        )
    }
}

struct BuildResult: Sendable {
    var succeeded: Bool
    var pdfURL: URL?
    var issues: [BuildIssue]
    var rawLog: String
}
