import Foundation

struct WorkspaceID: Hashable, Codable, Sendable {
    var rawValue: UUID = UUID()
}

struct Workspace: Identifiable, Hashable, Codable, Sendable {
    var id: WorkspaceID
    var rootURL: URL
    var mainFileURL: URL?
    var displayName: String
}

struct TextLocation: Hashable, Codable, Sendable {
    var fileURL: URL
    var line: Int
    var column: Int
}

struct SourceRange: Hashable, Codable, Sendable {
    var fileURL: URL
    var startLine: Int
    var startColumn: Int
    var endLine: Int
    var endColumn: Int
}

enum IssueSeverity: String, Codable, Sendable {
    case error
    case warning
    case note
}

struct BuildIssue: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var severity: IssueSeverity
    var message: String
    var location: TextLocation?
    var rawLogExcerpt: String
}

struct EditorJump: Identifiable, Equatable {
    var id = UUID()
    var location: TextLocation
}

enum FilePresentation: Equatable {
    case none
    case text
    case pdf(URL)
    case image(URL)
    case external(URL)
}
