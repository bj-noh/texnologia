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

struct WorkspaceSession: Identifiable, Equatable {
    var id: WorkspaceID { workspace.id }
    var workspace: Workspace
    var index: ProjectIndex

    static func == (lhs: WorkspaceSession, rhs: WorkspaceSession) -> Bool {
        lhs.workspace == rhs.workspace
    }
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

struct TextFilePreview: Equatable {
    var fileURL: URL
    var text: String
    var byteCount: Int
    var previewedByteCount: Int
    var encodingDescription: String

    var isTruncated: Bool {
        previewedByteCount < byteCount
    }
}

struct HistoryEntry: Identifiable, Hashable {
    var id = UUID()
    var fileURL: URL
    var fileName: String
    var text: String
    var createdAt: Date
    var reason: String
}

enum PreviewPaneID: String, Codable, Equatable {
    case primary
    case secondary

    var displayName: String {
        switch self {
        case .primary: return "A"
        case .secondary: return "B"
        }
    }
}

enum FilePresentation: Equatable {
    case none
    case text
    case readOnlyText(TextFilePreview)
    case pdf(URL)
    case image(URL)
    case external(URL)
}
