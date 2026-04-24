import SwiftUI

struct PendingEditReviewView: View {
    @ObservedObject var appModel: AppModel
    let edit: PendingEdit

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            hunksList
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text("AI proposed edit")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(edit.fileURL.lastPathComponent) · \(edit.hunks.count) hunk\(edit.hunks.count == 1 ? "" : "s") · \(edit.pendingCount) pending")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Accept All") { appModel.acceptAllPendingHunks() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(edit.pendingCount == 0)
                .help("Apply the AI proposal for every pending hunk")

            Button("Reject All") { appModel.rejectAllPendingHunks() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(edit.pendingCount == 0)
                .help("Keep the original content for every pending hunk")

            Button(role: .destructive) {
                appModel.discardPendingEdit()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Discard this proposal without applying any hunk")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var hunksList: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(edit.hunks) { hunk in
                    PendingHunkRowView(hunk: hunk, appModel: appModel)
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 620)
    }
}

private struct PendingHunkRowView: View {
    let hunk: PendingHunk
    @ObservedObject var appModel: AppModel

    @State private var yourVersionText: String = ""
    @State private var didInitialize: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            body(for: hunk.status)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { initializeIfNeeded() }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(hunk.hunk.header)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            statusBadge

            Spacer()

            if hunk.status == .pending {
                Button {
                    let edited = yourVersionText
                    appModel.updatePendingHunkEdit(id: hunk.id, replacement: edited)
                    appModel.confirmPendingHunkEdit(id: hunk.id)
                } label: {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
                .help("Apply the text in the editable pane below")

                Button {
                    yourVersionText = aiSuggestionText
                } label: {
                    Label("Use AI", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy the AI suggestion into the editable pane")

                Button {
                    yourVersionText = originalText
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Restore the editable pane to the original file content")

                Button { appModel.rejectPendingHunk(id: hunk.id) } label: {
                    Label("Reject", systemImage: "xmark.circle")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .help("Keep the original content and discard this AI change")
            } else {
                Button("Reopen") { reopenHunk() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Bring this hunk back to pending for another review")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(headerBackground)
    }

    @ViewBuilder
    private func body(for status: PendingHunkStatus) -> some View {
        if status == .pending {
            activeDualPane
        } else {
            diffOverview
        }
    }

    private var activeDualPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("AI suggestion")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        copyToClipboard(aiSuggestionText)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Copy AI suggestion to clipboard")
                }

                ScrollView(.vertical) {
                    Text(aiSuggestionText.isEmpty ? " " : aiSuggestionText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 180)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.30), lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Your version (editable)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(isModifiedFromOriginal ? "modified" : "original")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                TextEditor(text: $yourVersionText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 220)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.orange.opacity(0.50), lineWidth: 0.8)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(14)
    }

    private var diffOverview: some View {
        VStack(spacing: 0) {
            ForEach(hunk.hunk.lines) { line in
                PendingDiffLineRow(line: line)
            }
        }
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(statusColor.opacity(0.18))
            )
            .foregroundStyle(statusColor)
    }

    private var statusLabel: String {
        switch hunk.status {
        case .pending: return "PENDING"
        case .accepted: return "ACCEPTED"
        case .rejected: return "REJECTED"
        case .edited: return "EDITED"
        }
    }

    private var statusColor: Color {
        switch hunk.status {
        case .pending: return .orange
        case .accepted: return .green
        case .rejected: return .red
        case .edited: return .accentColor
        }
    }

    private var headerBackground: Color {
        switch hunk.status {
        case .pending: return Color(nsColor: .quaternaryLabelColor).opacity(0.18)
        case .accepted: return Color.green.opacity(0.10)
        case .rejected: return Color.red.opacity(0.08)
        case .edited: return Color.accentColor.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch hunk.status {
        case .pending: return Color(nsColor: .separatorColor).opacity(0.5)
        case .accepted: return Color.green.opacity(0.35)
        case .rejected: return Color.red.opacity(0.30)
        case .edited: return Color.accentColor.opacity(0.35)
        }
    }

    private var aiSuggestionText: String {
        hunk.hunk.lines.compactMap { $0.kind == .removed ? nil : $0.text }.joined(separator: "\n")
    }

    private var originalText: String {
        hunk.hunk.lines.compactMap { $0.kind == .added ? nil : $0.text }.joined(separator: "\n")
    }

    private var isModifiedFromOriginal: Bool {
        yourVersionText != originalText
    }

    private func initializeIfNeeded() {
        guard !didInitialize else { return }
        didInitialize = true
        yourVersionText = hunk.editedReplacement ?? originalText
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func reopenHunk() {
        guard var edit = appModel.pendingEdit,
              let idx = edit.hunks.firstIndex(where: { $0.id == hunk.id }) else { return }
        edit.hunks[idx].status = .pending
        edit.hunks[idx].editedReplacement = nil
        appModel.pendingEdit = edit
        yourVersionText = originalText
        didInitialize = true
    }
}

private struct PendingDiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: 32, alignment: .trailing)
                .padding(.trailing, 4)
                .foregroundStyle(.tertiary)

            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 32, alignment: .trailing)
                .padding(.trailing, 4)
                .foregroundStyle(.tertiary)

            Text(prefix)
                .frame(width: 12, alignment: .center)
                .foregroundStyle(prefixColor)

            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 10)

            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private var prefix: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "−"
        case .context: return " "
        }
    }

    private var prefixColor: Color {
        switch line.kind {
        case .added: return Color(red: 0.10, green: 0.60, blue: 0.24)
        case .removed: return Color(red: 0.74, green: 0.22, blue: 0.24)
        case .context: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .added: return Color(red: 0.06, green: 0.38, blue: 0.14)
        case .removed: return Color(red: 0.52, green: 0.12, blue: 0.14)
        case .context: return Color(nsColor: .labelColor).opacity(0.82)
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: return Color.green.opacity(0.12)
        case .removed: return Color.red.opacity(0.10)
        case .context: return Color.clear
        }
    }
}
