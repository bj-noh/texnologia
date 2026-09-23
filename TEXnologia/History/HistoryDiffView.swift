import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum HistoryCompareTarget: Hashable {
    case currentEditor
    case base
    case snapshot(UUID)
}

struct HistoryDiffPopover: View {
    var entries: [HistoryEntry]
    var currentEditorText: String
    var currentEditorFileURL: URL?
    var restore: (HistoryEntry) -> Void

    @State private var selectedEntryID: UUID?
    @State private var compareTarget: HistoryCompareTarget = .currentEditor
    @State private var baseEntryID: UUID?

    var fileFilteredEntries: [HistoryEntry] {
        HistoryDiffPopover.filter(entries: entries, forFileURL: currentEditorFileURL)
    }

    static func filter(entries: [HistoryEntry], forFileURL fileURL: URL?) -> [HistoryEntry] {
        guard let fileURL else { return entries }
        return entries.filter { $0.fileURL == fileURL }
    }

    var body: some View {
        HStack(spacing: 0) {
            snapshotList
                .frame(width: 240)
                .background(HistoryDiffStyle.sidebarBackground)

            FolioTheme.border.frame(width: 1)

            VStack(spacing: 0) {
                diffHeader
                FolioTheme.border.frame(height: 1)
                diffBody
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 860, height: 560)
        .foregroundStyle(FolioTheme.text)
        .tint(FolioTheme.accent)
        .onAppear {
            let scoped = fileFilteredEntries
            if selectedEntryID == nil || !scoped.contains(where: { $0.id == selectedEntryID }) {
                selectedEntryID = scoped.first?.id
            }
            if let baseID = baseEntryID, !scoped.contains(where: { $0.id == baseID }) {
                baseEntryID = nil
                if compareTarget == .base { compareTarget = .currentEditor }
            }
        }
        .onChange(of: currentEditorFileURL) { _, _ in
            let scoped = fileFilteredEntries
            selectedEntryID = scoped.first?.id
            if let baseID = baseEntryID, !scoped.contains(where: { $0.id == baseID }) {
                baseEntryID = nil
                if compareTarget == .base { compareTarget = .currentEditor }
            }
        }
        .onChange(of: entries) { _, _ in
            let scoped = fileFilteredEntries
            if let current = selectedEntryID, !scoped.contains(where: { $0.id == current }) {
                selectedEntryID = scoped.first?.id
            }
            if let baseID = baseEntryID, !scoped.contains(where: { $0.id == baseID }) {
                baseEntryID = nil
                if compareTarget == .base { compareTarget = .currentEditor }
            }
        }
    }

    // MARK: - Snapshot list

    private var snapshotList: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(FolioTheme.accent)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version history")
                        .font(.system(size: 12, weight: .semibold))
                    if let fileURL = currentEditorFileURL {
                        Text(fileURL.lastPathComponent)
                            .font(.system(size: 10))
                            .foregroundStyle(FolioTheme.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Text("\(fileFilteredEntries.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FolioTheme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(FolioTheme.surface, in: RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 18)

            if fileFilteredEntries.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(FolioTheme.subtle)
                    Text("No snapshots yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FolioTheme.muted)
                }
                Spacer()
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(fileFilteredEntries) { entry in
                            SnapshotRow(
                                entry: entry,
                                isSelected: entry.id == selectedEntryID,
                                isBase: entry.id == baseEntryID,
                                stats: stats(for: entry)
                            )
                            .onTapGesture {
                                selectedEntryID = entry.id
                            }
                            .contextMenu {
                                if entry.id == baseEntryID {
                                    Button("Clear Base") {
                                        baseEntryID = nil
                                        if compareTarget == .base { compareTarget = .currentEditor }
                                    }
                                } else {
                                    Button("Set as Base") {
                                        baseEntryID = entry.id
                                        compareTarget = .base
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Diff header

    private var diffHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let entry = selectedEntry {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.fileName)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text("\(entry.reason) · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10))
                            .foregroundStyle(FolioTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    DiffStatsBadge(stats: currentStats)
                } else {
                    Text("Select a snapshot")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FolioTheme.muted)
                }
            }

            if let _ = selectedEntry {
                HStack(spacing: 10) {
                    Text("Compare with")
                        .font(.system(size: 10))
                        .foregroundStyle(FolioTheme.muted)
                    Picker("", selection: $compareTarget) {
                        Text("Current document").tag(HistoryCompareTarget.currentEditor)
                        if let baseID = baseEntryID,
                           let baseEntry = fileFilteredEntries.first(where: { $0.id == baseID }) {
                            Text("Base (\(baseEntry.createdAt.formatted(date: .omitted, time: .shortened)))")
                                .tag(HistoryCompareTarget.base)
                        }
                        ForEach(comparisonCandidates, id: \.self) { candidate in
                            Text(label(for: candidate)).tag(HistoryCompareTarget.snapshot(candidate))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .help("Select what to compare the selected snapshot against")

                    Spacer(minLength: 4)

                    Menu {
                        Button("Copy DIF LaTeX to Clipboard") { copyDIFToClipboard() }
                        Button("Save DIF LaTeX…") { saveDIFToFile() }
                    } label: {
                        Label("DIF", systemImage: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .fixedSize()
                    .foregroundStyle(FolioTheme.muted)
                    .help("Export diff with \\DIFadd / \\DIFdel markup")

                    Button {
                        if let entry = selectedEntry {
                            restore(entry)
                        }
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(FolioPrimaryButtonStyle())
                    .controlSize(.small)
                }
            }
        }
        .padding(20)
        .background(HistoryDiffStyle.headerBackground)
    }

    // MARK: - Diff body

    private var diffBody: some View {
        Group {
            if selectedEntry == nil {
                emptyState
            } else if currentStats.isIdentical {
                identicalState
            } else {
                DiffHunksView(hunks: currentHunks)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HistoryDiffStyle.diffBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(FolioTheme.accent)
                .frame(width: 58, height: 58)
                .background(FolioTheme.accentSoft, in: RoundedRectangle(cornerRadius: 15))
            Text("Every version tells a story.")
                .font(.system(size: 16, weight: .semibold))
            Text("Choose a snapshot to see what's changed\nin your document.")
                .font(.system(size: 12))
                .foregroundStyle(FolioTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var identicalState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(FolioTheme.accent)
                .frame(width: 58, height: 58)
                .background(FolioTheme.accentSoft, in: RoundedRectangle(cornerRadius: 15))
            Text("Everything matches.")
                .font(.system(size: 16, weight: .semibold))
            Text("These versions have the same content.")
                .font(.system(size: 12))
                .foregroundStyle(FolioTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Derived state

    private var selectedEntry: HistoryEntry? {
        guard let id = selectedEntryID else { return nil }
        return fileFilteredEntries.first(where: { $0.id == id })
    }

    var comparisonBaseText: String {
        switch compareTarget {
        case .currentEditor:
            return currentEditorText
        case .base:
            guard let baseID = baseEntryID else { return currentEditorText }
            return fileFilteredEntries.first(where: { $0.id == baseID })?.text ?? currentEditorText
        case .snapshot(let id):
            return fileFilteredEntries.first(where: { $0.id == id })?.text ?? ""
        }
    }

    private var comparisonCandidates: [UUID] {
        guard let selected = selectedEntry else { return [] }
        return fileFilteredEntries
            .filter { $0.id != selected.id && $0.id != baseEntryID }
            .prefix(12)
            .map(\.id)
    }

    private func label(for id: UUID) -> String {
        guard let entry = fileFilteredEntries.first(where: { $0.id == id }) else { return "…" }
        return "vs " + entry.createdAt.formatted(date: .omitted, time: .shortened)
    }

    private var currentDiffLines: [DiffLine] {
        guard let selected = selectedEntry else { return [] }
        return HistoryDiffComputer.computeLines(from: selected.text, to: comparisonBaseText)
    }

    private var currentHunks: [DiffHunk] {
        HistoryDiffComputer.collapseToHunks(currentDiffLines)
    }

    private var currentStats: DiffStats {
        HistoryDiffComputer.stats(for: currentDiffLines)
    }

    private func stats(for entry: HistoryEntry) -> DiffStats {
        let baseText: String
        switch compareTarget {
        case .currentEditor: baseText = currentEditorText
        case .base:
            if let baseID = baseEntryID, let baseEntry = fileFilteredEntries.first(where: { $0.id == baseID }) {
                baseText = baseEntry.text
            } else {
                baseText = currentEditorText
            }
        case .snapshot(let id):
            baseText = fileFilteredEntries.first(where: { $0.id == id })?.text ?? currentEditorText
        }
        let lines = HistoryDiffComputer.computeLines(from: entry.text, to: baseText)
        return HistoryDiffComputer.stats(for: lines)
    }

    private var currentDIFLatex: String {
        guard let selected = selectedEntry else { return "" }
        return LatexDiffExporter.export(from: selected.text, to: comparisonBaseText)
    }

    private func copyDIFToClipboard() {
        let text = currentDIFLatex
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func saveDIFToFile() {
        let text = currentDIFLatex
        guard !text.isEmpty, let entry = selectedEntry else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = defaultDIFFileName(for: entry)
        panel.message = "Save LaTeX with \\DIFadd / \\DIFdel markup"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.data(using: .utf8)?.write(to: url, options: [.atomic])
        }
    }

    private func defaultDIFFileName(for entry: HistoryEntry) -> String {
        let base = (entry.fileName as NSString).deletingPathExtension
        return "\(base)-diff.tex"
    }
}

// MARK: - Snapshot row

private struct SnapshotRow: View {
    let entry: HistoryEntry
    let isSelected: Bool
    var isBase: Bool = false
    let stats: DiffStats

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isBase ? "flag.fill" : "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(isBase ? Color.orange : (isSelected ? FolioTheme.accent : FolioTheme.subtle))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(entry.fileName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    if isBase {
                        Text("BASE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().stroke(Color.orange.opacity(0.7), lineWidth: 0.5)
                            )
                    }
                }

                Text("\(entry.reason) · \(entry.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 9))
                    .foregroundStyle(FolioTheme.muted)
                    .lineLimit(1)

                if !stats.isIdentical {
                    HStack(spacing: 4) {
                        if stats.added > 0 {
                            Text("+\(stats.added)")
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(HistoryDiffStyle.addedForeground)
                        }
                        if stats.removed > 0 {
                            Text("−\(stats.removed)")
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(HistoryDiffStyle.removedForeground)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? FolioTheme.accentSoft : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Diff stats badge

private struct DiffStatsBadge: View {
    let stats: DiffStats

    var body: some View {
        HStack(spacing: 4) {
            if stats.added > 0 {
                Text("+\(stats.added)")
                    .foregroundStyle(HistoryDiffStyle.addedForeground)
            }
            if stats.removed > 0 {
                Text("−\(stats.removed)")
                    .foregroundStyle(HistoryDiffStyle.removedForeground)
            }
            if stats.isIdentical {
                Text("No changes")
                    .foregroundStyle(FolioTheme.muted)
            }
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(FolioTheme.canvas)
        )
    }
}

// MARK: - Diff hunks view

private struct DiffHunksView: View {
    let hunks: [DiffHunk]

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(hunks) { hunk in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(hunk.header)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(HistoryDiffStyle.hunkHeaderForeground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(HistoryDiffStyle.hunkHeaderBackground)

                        ForEach(hunk.lines) { line in
                            DiffLineRow(line: line)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(HistoryDiffStyle.hunkBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(18)
        }
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)
                .foregroundStyle(FolioTheme.subtle)

            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)
                .foregroundStyle(FolioTheme.subtle)

            Text(prefix)
                .frame(width: 14, alignment: .center)
                .foregroundStyle(prefixForeground)

            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(textForeground)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 12)

            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
    }

    private var prefix: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "−"
        case .context: return " "
        }
    }

    private var prefixForeground: Color {
        switch line.kind {
        case .added: return HistoryDiffStyle.addedForeground
        case .removed: return HistoryDiffStyle.removedForeground
        case .context: return FolioTheme.subtle
        }
    }

    private var textForeground: Color {
        switch line.kind {
        case .added: return HistoryDiffStyle.addedTextForeground
        case .removed: return HistoryDiffStyle.removedTextForeground
        case .context: return FolioTheme.text
        }
    }

    private var rowBackground: Color {
        switch line.kind {
        case .added: return HistoryDiffStyle.addedBackground
        case .removed: return HistoryDiffStyle.removedBackground
        case .context: return Color.clear
        }
    }
}

// MARK: - Style

private enum HistoryDiffStyle {
    static let sidebarBackground = FolioTheme.sidebar
    static let headerBackground = FolioTheme.surface
    static let diffBackground = FolioTheme.surface

    static let addedBackground = Color.green.opacity(0.12)
    static let removedBackground = Color.red.opacity(0.10)
    static let addedForeground = Color(red: 0.10, green: 0.60, blue: 0.24)
    static let removedForeground = Color(red: 0.74, green: 0.22, blue: 0.24)
    static let addedTextForeground = Color(red: 0.06, green: 0.38, blue: 0.14)
    static let removedTextForeground = Color(red: 0.52, green: 0.12, blue: 0.14)

    static let hunkHeaderBackground = FolioTheme.canvas
    static let hunkHeaderForeground = FolioTheme.muted
    static let hunkBorder = FolioTheme.border
}
