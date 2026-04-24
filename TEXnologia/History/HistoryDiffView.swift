import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum HistoryCompareTarget: Hashable {
    case currentEditor
    case snapshot(UUID)
}

struct HistoryDiffPopover: View {
    var entries: [HistoryEntry]
    var currentEditorText: String
    var currentEditorFileURL: URL?
    var restore: (HistoryEntry) -> Void

    @State private var selectedEntryID: UUID?
    @State private var compareTarget: HistoryCompareTarget = .currentEditor

    var body: some View {
        HStack(spacing: 0) {
            snapshotList
                .frame(width: 240)
                .background(HistoryDiffStyle.sidebarBackground)

            Divider()

            VStack(spacing: 0) {
                diffHeader
                Divider()
                diffBody
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 860, height: 560)
        .onAppear {
            if selectedEntryID == nil, let first = entries.first {
                selectedEntryID = first.id
            }
        }
        .onChange(of: entries) { _, newValue in
            if let current = selectedEntryID, !newValue.contains(where: { $0.id == current }) {
                selectedEntryID = newValue.first?.id
            }
        }
    }

    // MARK: - Snapshot list

    private var snapshotList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Snapshots")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entries.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if entries.isEmpty {
                Spacer()
                ContentUnavailableView("No History", systemImage: "clock")
                    .font(.caption)
                Spacer()
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries) { entry in
                            SnapshotRow(
                                entry: entry,
                                isSelected: entry.id == selectedEntryID,
                                stats: stats(for: entry)
                            )
                            .onTapGesture {
                                selectedEntryID = entry.id
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Diff header

    private var diffHeader: some View {
        HStack(spacing: 10) {
            if let entry = selectedEntry {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.fileName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text("\(entry.reason) · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Select a snapshot")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let _ = selectedEntry {
                DiffStatsBadge(stats: currentStats)

                Picker("", selection: $compareTarget) {
                    Text("vs Current").tag(HistoryCompareTarget.currentEditor)
                    ForEach(comparisonCandidates, id: \.self) { candidate in
                        Text(label(for: candidate)).tag(HistoryCompareTarget.snapshot(candidate))
                    }
                }
                .labelsHidden()
                .frame(width: 170)

                Menu {
                    Button("Copy DIF LaTeX to Clipboard") { copyDIFToClipboard() }
                    Button("Save DIF LaTeX…") { saveDIFToFile() }
                } label: {
                    Label("DIF", systemImage: "square.and.arrow.up.on.square")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
                .help("Export diff with \\DIFadd / \\DIFdel markup")

                Button {
                    if let entry = selectedEntry {
                        restore(entry)
                    }
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text("히스토리 스냅샷을 선택하면 현재 편집 중인 문서와의 차이를 보여줍니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var identicalState: some View {
        VStack(spacing: 6) {
            Image(systemName: "equal.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.green.opacity(0.7))
            Text("변경 사항이 없습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Derived state

    private var selectedEntry: HistoryEntry? {
        guard let id = selectedEntryID else { return nil }
        return entries.first(where: { $0.id == id })
    }

    private var comparisonBaseText: String {
        switch compareTarget {
        case .currentEditor:
            return currentEditorText
        case .snapshot(let id):
            return entries.first(where: { $0.id == id })?.text ?? ""
        }
    }

    private var comparisonCandidates: [UUID] {
        guard let selected = selectedEntry else { return [] }
        return entries
            .filter { $0.id != selected.id }
            .prefix(12)
            .map(\.id)
    }

    private func label(for id: UUID) -> String {
        guard let entry = entries.first(where: { $0.id == id }) else { return "…" }
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
        let lines = HistoryDiffComputer.computeLines(from: entry.text, to: currentEditorText)
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
    let stats: DiffStats

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                Text("\(entry.reason) · \(entry.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
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
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
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
                Text("identical")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
        )
    }
}

// MARK: - Diff hunks view

private struct DiffHunksView: View {
    let hunks: [DiffHunk]

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(hunks) { hunk in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(hunk.header)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(HistoryDiffStyle.hunkHeaderForeground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(HistoryDiffStyle.hunkHeaderBackground)

                        ForEach(hunk.lines) { line in
                            DiffLineRow(line: line)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(HistoryDiffStyle.hunkBorder, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(12)
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
                .foregroundStyle(.tertiary)

            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)
                .foregroundStyle(.tertiary)

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
        case .context: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var textForeground: Color {
        switch line.kind {
        case .added: return HistoryDiffStyle.addedTextForeground
        case .removed: return HistoryDiffStyle.removedTextForeground
        case .context: return Color(nsColor: .labelColor).opacity(0.82)
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
    static let sidebarBackground = Color(nsColor: .controlBackgroundColor).opacity(0.55)
    static let headerBackground = Color(nsColor: .windowBackgroundColor).opacity(0.6)
    static let diffBackground = Color(nsColor: .textBackgroundColor)

    static let addedBackground = Color.green.opacity(0.12)
    static let removedBackground = Color.red.opacity(0.10)
    static let addedForeground = Color(red: 0.10, green: 0.60, blue: 0.24)
    static let removedForeground = Color(red: 0.74, green: 0.22, blue: 0.24)
    static let addedTextForeground = Color(red: 0.06, green: 0.38, blue: 0.14)
    static let removedTextForeground = Color(red: 0.52, green: 0.12, blue: 0.14)

    static let hunkHeaderBackground = Color(nsColor: .quaternaryLabelColor).opacity(0.25)
    static let hunkHeaderForeground = Color.secondary
    static let hunkBorder = Color(nsColor: .separatorColor).opacity(0.45)
}
