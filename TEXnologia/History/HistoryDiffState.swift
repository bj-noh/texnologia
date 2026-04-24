import Foundation

struct HistoryDiffState: Equatable {
    var entries: [HistoryEntry]
    var currentEditorText: String
    var currentEditorFileURL: URL?
    var selectedEntryID: UUID?
    var compareTarget: HistoryCompareTarget
    var baseEntryID: UUID?

    init(
        entries: [HistoryEntry] = [],
        currentEditorText: String = "",
        currentEditorFileURL: URL? = nil,
        selectedEntryID: UUID? = nil,
        compareTarget: HistoryCompareTarget = .currentEditor,
        baseEntryID: UUID? = nil
    ) {
        self.entries = entries
        self.currentEditorText = currentEditorText
        self.currentEditorFileURL = currentEditorFileURL
        self.selectedEntryID = selectedEntryID
        self.compareTarget = compareTarget
        self.baseEntryID = baseEntryID
    }

    var fileFilteredEntries: [HistoryEntry] {
        guard let fileURL = currentEditorFileURL else { return entries }
        return entries.filter { $0.fileURL == fileURL }
    }

    var selectedEntry: HistoryEntry? {
        guard let id = selectedEntryID else { return nil }
        return fileFilteredEntries.first(where: { $0.id == id })
    }

    var baseEntry: HistoryEntry? {
        guard let id = baseEntryID else { return nil }
        return fileFilteredEntries.first(where: { $0.id == id })
    }

    var comparisonBaseText: String {
        switch compareTarget {
        case .currentEditor:
            return currentEditorText
        case .base:
            return baseEntry?.text ?? currentEditorText
        case .snapshot(let id):
            return fileFilteredEntries.first(where: { $0.id == id })?.text ?? ""
        }
    }

    var diffLines: [DiffLine] {
        guard let selected = selectedEntry else { return [] }
        return HistoryDiffComputer.computeLines(from: selected.text, to: comparisonBaseText)
    }

    var diffStats: DiffStats {
        HistoryDiffComputer.stats(for: diffLines)
    }

    func stats(for entry: HistoryEntry) -> DiffStats {
        let lines = HistoryDiffComputer.computeLines(from: entry.text, to: comparisonBaseText)
        return HistoryDiffComputer.stats(for: lines)
    }

    mutating func normalize() {
        let scoped = fileFilteredEntries
        if let current = selectedEntryID, !scoped.contains(where: { $0.id == current }) {
            selectedEntryID = scoped.first?.id
        } else if selectedEntryID == nil {
            selectedEntryID = scoped.first?.id
        }
        if let baseID = baseEntryID, !scoped.contains(where: { $0.id == baseID }) {
            baseEntryID = nil
            if compareTarget == .base { compareTarget = .currentEditor }
        }
    }
}
