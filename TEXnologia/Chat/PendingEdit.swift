import Foundation

enum PendingHunkStatus: Equatable {
    case pending
    case accepted
    case rejected
    case edited
}

struct PendingHunk: Identifiable, Equatable {
    let id: UUID
    let hunk: DiffHunk
    var status: PendingHunkStatus
    var editedReplacement: String?

    var replacementLines: [String] {
        if let editedReplacement {
            if editedReplacement.isEmpty { return [] }
            return editedReplacement.components(separatedBy: "\n")
        }
        switch status {
        case .accepted, .edited:
            return hunk.lines.compactMap { line in
                line.kind == .removed ? nil : line.text
            }
        case .rejected:
            return hunk.lines.compactMap { line in
                line.kind == .added ? nil : line.text
            }
        case .pending:
            return hunk.lines.compactMap { line in
                line.kind == .added ? nil : line.text
            }
        }
    }

    var originalLineCount: Int {
        hunk.lines.filter { $0.kind != .added }.count
    }

    var firstOldLineNumber: Int? {
        hunk.lines.compactMap(\.oldLineNumber).first
    }
}

struct PendingEdit: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let originalText: String
    let proposedText: String
    var hunks: [PendingHunk]

    init(fileURL: URL, originalText: String, proposedText: String) {
        self.id = UUID()
        self.fileURL = fileURL
        self.originalText = originalText
        self.proposedText = proposedText

        let lines = HistoryDiffComputer.computeLines(from: originalText, to: proposedText)
        let rawHunks = HistoryDiffComputer.collapseToHunks(lines, context: 3)
        self.hunks = rawHunks.map { hunk in
            PendingHunk(id: UUID(), hunk: hunk, status: .pending, editedReplacement: nil)
        }
    }

    var isEmpty: Bool { hunks.isEmpty }

    var allResolved: Bool {
        hunks.allSatisfy { $0.status != .pending }
    }

    var pendingCount: Int {
        hunks.filter { $0.status == .pending }.count
    }

    func resolvedText() -> String {
        guard !hunks.isEmpty else { return originalText }

        let originalLines = splitLines(originalText)
        var result: [String] = []
        var cursor = 0

        for hunk in hunks {
            let hunkStart = (hunk.firstOldLineNumber ?? (cursor + 1)) - 1
            if hunkStart > cursor {
                result.append(contentsOf: originalLines[cursor..<min(hunkStart, originalLines.count)])
            }
            result.append(contentsOf: hunk.replacementLines)
            cursor = min(hunkStart + hunk.originalLineCount, originalLines.count)
        }
        if cursor < originalLines.count {
            result.append(contentsOf: originalLines[cursor..<originalLines.count])
        }

        var joined = result.joined(separator: "\n")
        if originalText.hasSuffix("\n") && !joined.hasSuffix("\n") {
            joined.append("\n")
        }
        return joined
    }

    private func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n"), lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}
