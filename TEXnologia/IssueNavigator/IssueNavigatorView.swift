import SwiftUI

struct IssueDockView: View {
    var issues: [BuildIssue]
    @Binding var isExpanded: Bool
    var onSelect: (BuildIssue) -> Void

    private var errorCount: Int {
        issues.filter { $0.severity == .error }.count
    }

    private var warningCount: Int {
        issues.filter { $0.severity == .warning }.count
    }

    private var firstIssue: BuildIssue? {
        issues.first { $0.severity == .error } ?? issues.first
    }

    var body: some View {
        VStack(spacing: 0) {
            compactBar

            if isExpanded {
                Divider()
                IssueNavigatorView(issues: issues, onSelect: onSelect)
            }
        }
        .background(.bar)
    }

    private var compactBar: some View {
        HStack(spacing: 10) {
            Image(systemName: errorCount > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(errorCount > 0 ? .red : .orange)

            Text(summaryText)
                .font(.caption)
                .fontWeight(.semibold)

            if let firstIssue {
                Text(firstIssue.location.map { "\($0.fileURL.lastPathComponent):\($0.line)" } ?? "Compile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(firstIssue.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let firstIssue {
                Button {
                    onSelect(firstIssue)
                } label: {
                    Label("First", systemImage: "arrowshape.turn.up.right")
                }
                .controlSize(.small)
            }

            Button {
                isExpanded.toggle()
            } label: {
                Label(isExpanded ? "Hide Issues" : "Show Issues", systemImage: isExpanded ? "chevron.down" : "chevron.up")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .contentShape(Rectangle())
    }

    private var summaryText: String {
        if errorCount > 0 {
            return "\(errorCount) error\(errorCount == 1 ? "" : "s")"
        }
        return "\(warningCount) warning\(warningCount == 1 ? "" : "s")"
    }
}

struct IssueNavigatorView: View {
    var issues: [BuildIssue]
    var onSelect: (BuildIssue) -> Void
    @State private var selectedIssueID: BuildIssue.ID?
    @State private var showsRawLog = false

    private var selectedIssue: BuildIssue? {
        if let selectedIssueID {
            return issues.first { $0.id == selectedIssueID }
        }
        return issues.first
    }

    var body: some View {
        HSplitView {
            List(selection: $selectedIssueID) {
                ForEach(issues) { issue in
                    Button {
                        selectedIssueID = issue.id
                        onSelect(issue)
                    } label: {
                        IssueRow(issue: issue)
                    }
                    .buttonStyle(.plain)
                    .tag(issue.id)
                }
            }
            .frame(minWidth: 360)

            IssueDetailView(issue: selectedIssue, showsRawLog: $showsRawLog, onSelect: onSelect)
                .frame(minWidth: 360)
        }
        .onAppear {
            selectedIssueID = selectedIssueID ?? issues.first?.id
        }
    }
}

private struct IssueRow: View {
    var issue: BuildIssue

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? .red : .orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(issue.message)
                    .font(.caption)
                    .lineLimit(1)
                Text(issue.location.map { "\($0.fileURL.lastPathComponent):\($0.line)" } ?? "Compile")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 3)
    }
}

private struct IssueDetailView: View {
    var issue: BuildIssue?
    @Binding var showsRawLog: Bool
    var onSelect: (BuildIssue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let issue {
                HStack {
                    Label(issue.severity.rawValue.capitalized, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.severity == .error ? .red : .orange)
                        .font(.headline)

                    Spacer()

                    Button("Jump to Source") {
                        onSelect(issue)
                    }
                    .disabled(issue.location == nil)
                }

                Text(issue.message)
                    .font(.body)
                    .textSelection(.enabled)

                if let location = issue.location {
                    Text("\(location.fileURL.path):\(location.line):\(location.column)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                DisclosureGroup("Raw Log", isExpanded: $showsRawLog) {
                    ScrollView {
                        Text(issue.rawLogExcerpt.isEmpty ? "No raw log excerpt was captured." : issue.rawLogExcerpt)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(maxHeight: 120)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else {
                Text("No issue selected.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
    }
}
