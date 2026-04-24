import Foundation

struct ProjectIndex: Equatable, Sendable {
    var rootURL: URL?
    var rootFiles: [URL]
    var texFiles: [URL]
    var bibFiles: [URL]
    var outline: [OutlineItem]
    var labels: [String: TextLocation]
    var citationKeys: [String]

    static let empty = ProjectIndex(
        rootURL: nil,
        rootFiles: [],
        texFiles: [],
        bibFiles: [],
        outline: [],
        labels: [:],
        citationKeys: []
    )
}

struct OutlineItem: Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var level: Int
    var location: TextLocation
}

