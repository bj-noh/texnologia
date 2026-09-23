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
                FolioTheme.border.frame(height: 1)
                IssueNavigatorView(issues: issues, onSelect: onSelect)
            }
        }
        .foregroundStyle(FolioTheme.text)
        .tint(FolioTheme.accent)
        .background(FolioTheme.surface)
    }

    private var compactBar: some View {
        HStack(spacing: 10) {
            Image(systemName: errorCount > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(errorCount > 0 ? .red : .orange)
                .font(.system(size: 12))

            Text(summaryText)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background((errorCount > 0 ? Color.red : Color.orange).opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 5))

            if let firstIssue {
                Text(firstIssue.location.map { "\($0.fileURL.lastPathComponent):\($0.line)" } ?? "Compile")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(FolioTheme.muted)
                Text(firstIssue.message)
                    .font(.system(size: 11))
                    .foregroundStyle(FolioTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            if let firstIssue {
                Button {
                    onSelect(firstIssue)
                } label: {
                    Label("Go to first issue", systemImage: "arrow.up.right")
                }
                .buttonStyle(FolioSecondaryButtonStyle())
                .controlSize(.small)
            }
            Button {
                isExpanded.toggle()
            } label: {
                Label(isExpanded ? "Hide Issues" : "Show Issues", systemImage: isExpanded ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(FolioSecondaryButtonStyle())
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
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
                    .listRowSeparator(.hidden)
                    .listRowBackground(selectedIssueID == issue.id ? FolioTheme.accentSoft : Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.vertical, 6)
            .background(FolioTheme.sidebar)
            .frame(minWidth: 360)

            IssueDetailView(issue: selectedIssue, showsRawLog: $showsRawLog, onSelect: onSelect)
                .frame(minWidth: 360)
        }
        .foregroundStyle(FolioTheme.text)
        .tint(FolioTheme.accent)
        .background(FolioTheme.surface)
        .onAppear {
            selectedIssueID = selectedIssueID ?? issues.first?.id
        }
    }
}

private struct IssueRow: View {
    var issue: BuildIssue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? .red : .orange)
                .font(.system(size: 12))
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(issue.message)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(issue.location.map { "\($0.fileURL.lastPathComponent):\($0.line)" } ?? "Compile")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(FolioTheme.muted)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
    }
}

private struct IssueDetailView: View {
    var issue: BuildIssue?
    @Binding var showsRawLog: Bool
    var onSelect: (BuildIssue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let issue {
                HStack {
                    Label(issue.severity.rawValue.capitalized, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.severity == .error ? .red : .orange)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background((issue.severity == .error ? Color.red : Color.orange).opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    Button("Jump to Source") {
                        onSelect(issue)
                    }
                    .buttonStyle(FolioPrimaryButtonStyle())
                    .disabled(issue.location == nil)
                }

                Text(issue.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FolioTheme.text)
                    .lineSpacing(4)
                    .textSelection(.enabled)

                if let location = issue.location {
                    Text("\(location.fileURL.path):\(location.line):\(location.column)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(FolioTheme.muted)
                        .textSelection(.enabled)
                }

                DisclosureGroup("Build log", isExpanded: $showsRawLog) {
                    ScrollView {
                        Text(issue.rawLogExcerpt.isEmpty ? "No raw log excerpt was captured." : issue.rawLogExcerpt)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(FolioTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .frame(maxHeight: 120)
                    .background(FolioTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(FolioTheme.border, lineWidth: 1))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FolioTheme.muted)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(FolioTheme.accent)
                    Text("Select an issue to see the details.")
                        .font(.system(size: 12))
                        .foregroundStyle(FolioTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .padding(20)
        .background(FolioTheme.surface)
    }
}
