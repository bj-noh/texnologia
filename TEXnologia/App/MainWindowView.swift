import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct MainWindowView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isDropTarget = false
    @State private var issuePanelExpanded = false
    @State private var historyPresented = false
    @State private var rightPaneSplit = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack {
                if appModel.sessions.isEmpty {
                    WelcomeDropView(
                        isDropTarget: isDropTarget,
                        statusMessage: appModel.statusMessage,
                        openProject: appModel.openProjectPanel,
                        importZip: appModel.openZipPanel
                    )
                } else {
                    workspaceLayout
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTarget, perform: handleDrop)

            IssueDockView(
                issues: appModel.buildIssues,
                isExpanded: $issuePanelExpanded,
                onSelect: appModel.jumpToIssue
            )
            .frame(height: appModel.buildIssues.isEmpty ? 0 : (issuePanelExpanded ? 260 : 36))
            .animation(.easeInOut(duration: 0.16), value: issuePanelExpanded)
            .animation(.easeInOut(duration: 0.16), value: appModel.buildIssues)
        }
        .preferredColorScheme(appModel.settings.appearance.colorScheme)
        .onChange(of: appModel.buildIssues) { _, issues in
            if issues.isEmpty {
                issuePanelExpanded = false
            }
        }
    }

    private var workspaceLayout: some View {
        HSplitView {
            ProjectSidebarView(
                index: appModel.projectIndex,
                rootURL: appModel.workspace?.rootURL,
                mainFileURL: appModel.workspace?.mainFileURL,
                hidesIntermediateArtifacts: appModel.settings.hidesIntermediateArtifacts,
                selectedFileURL: $appModel.selectedFileURL,
                onSelectFile: appModel.selectFile,
                onMakeMainFile: appModel.setMainFile,
                onRefreshProject: appModel.refreshProject,
                onStatus: appModel.setStatus
            )
            .overlay(alignment: .top) {
                if appModel.sessions.count > 1 {
                    ProjectSessionsSidebarView(
                        sessions: appModel.sessions,
                        activeWorkspaceID: appModel.workspace?.id,
                        hidesIntermediateArtifacts: appModel.settings.hidesIntermediateArtifacts,
                        selectedFileURL: $appModel.selectedFileURL,
                        onActivateSession: appModel.activateSession,
                        onSelectFile: appModel.selectFile,
                        onMakeMainFile: appModel.setMainFile,
                        onStatus: appModel.setStatus
                    )
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

            CenterPaneView(
                presentation: appModel.selectedFilePresentation,
                selectedFileURL: appModel.selectedFileURL,
                text: $appModel.editorText,
                settings: appModel.settings,
                jump: appModel.editorJump
            )
            .frame(minWidth: 420)

            RightPreviewPane(
                focusedPane: $appModel.focusedPreviewPane,
                primaryPresentation: appModel.primaryPreviewPresentation,
                secondaryPresentation: appModel.secondaryPreviewPresentation,
                isSplit: rightPaneSplit
            )
                .frame(minWidth: 360)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            TEXnologiaMarkView(size: 26)

            Text(appModel.workspace?.displayName ?? "TEXnologia")
                .font(.headline)

            Text(appModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Picker("Engine", selection: $appModel.settings.defaultEngine) {
                ForEach(LatexEngine.allCases, id: \.self) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .onChange(of: appModel.settings.defaultEngine) { _, _ in
                appModel.updateSettings(appModel.settings)
            }
            .frame(width: 140)

            Picker("Year", selection: $appModel.settings.toolchainYear) {
                ForEach(TexToolchainYear.allCases, id: \.self) { year in
                    Text(year.displayName).tag(year)
                }
            }
            .onChange(of: appModel.settings.toolchainYear) { _, _ in
                appModel.updateSettings(appModel.settings)
            }
            .frame(width: 128)

            Button {
                historyPresented.toggle()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .popover(isPresented: $historyPresented) {
                HistoryPopover(entries: appModel.history, restore: appModel.restoreHistoryEntry)
            }

            Button {
                rightPaneSplit.toggle()
            } label: {
                Image(systemName: rightPaneSplit ? "rectangle.split.1x2" : "rectangle.split.2x1")
            }
            .help("Split preview pane")

            Button("Compile") {
                appModel.compile()
            }
            .keyboardShortcut("b", modifiers: [.command])
            .disabled(appModel.workspace?.mainFileURL == nil || appModel.isImporting)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.bar)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = fileURL(from: item) else { return }
                DispatchQueue.main.async {
                    appModel.openProjectResource(at: url)
                }
            }
            return true
        }

        return false
    }

    private func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return URL(string: string)
        }

        if let string = item as? String {
            return URL(string: string)
        }

        return nil
    }
}

private struct CenterPaneView: View {
    var presentation: FilePresentation
    var selectedFileURL: URL?
    @Binding var text: String
    var settings: AppSettings
    var jump: EditorJump?

    var body: some View {
        switch presentation {
        case .text:
            LaTeXEditorView(
                text: $text,
                settings: settings,
                syntaxMode: selectedFileURL?.editorSyntaxMode ?? .plain,
                jump: jump
            )
        case .readOnlyText(let preview):
            ReadOnlyTextPreviewPane(preview: preview)
        case .pdf(let url):
            PDFPaneView(documentURL: url)
        case .image(let url):
            ImagePreviewPane(fileURL: url)
        case .external(let url):
            FilePlaceholderView(
                icon: "doc",
                title: url.lastPathComponent,
                message: "This file type is not editable in TEXnologia yet.",
                fileURL: url
            )
        case .none:
            FilePlaceholderView(
                icon: "text.cursor",
                title: "No source file selected",
                message: "Choose a .tex, .bib, .sty, or .cls file from the explorer.",
                fileURL: selectedFileURL
            )
        }
    }
}

private struct RightPreviewPane: View {
    @Binding var focusedPane: PreviewPaneID
    var primaryPresentation: FilePresentation
    var secondaryPresentation: FilePresentation
    var isSplit: Bool

    var body: some View {
        if isSplit {
            VSplitView {
                PreviewPane(
                    paneID: .primary,
                    title: "Preview A",
                    presentation: primaryPresentation,
                    focusedPane: $focusedPane
                )
                    .frame(minHeight: 220)
                PreviewPane(
                    paneID: .secondary,
                    title: "Preview B",
                    presentation: secondaryPresentation,
                    focusedPane: $focusedPane
                )
                    .frame(minHeight: 180)
            }
        } else {
            PreviewPane(
                paneID: focusedPane,
                title: "Preview \(focusedPane.displayName)",
                presentation: focusedPresentation,
                focusedPane: $focusedPane
            )
        }
    }

    private var focusedPresentation: FilePresentation {
        focusedPane == .primary ? primaryPresentation : secondaryPresentation
    }
}

private struct PreviewPane: View {
    var paneID: PreviewPaneID
    var title: String
    var presentation: FilePresentation
    @Binding var focusedPane: PreviewPaneID

    private var isFocused: Bool {
        focusedPane == paneID
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(isFocused ? Color.orange : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(isFocused ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.bar)

            switch presentation {
            case .pdf(let url):
                PDFPaneView(documentURL: url)
            case .image(let url):
                ImagePreviewPane(fileURL: url)
            default:
                PDFPaneView(documentURL: nil)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedPane = paneID
        }
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .stroke(isFocused ? Color.orange : Color.clear, lineWidth: 1.25)
                .padding(1)
        }
    }
}

private struct HistoryPopover: View {
    var entries: [HistoryEntry]
    var restore: (HistoryEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.headline)
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 6)

            if entries.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock")
                    .frame(width: 340, height: 180)
            } else {
                List(entries) { entry in
                    Button {
                        restore(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.fileName)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("\(entry.reason) · \(entry.createdAt.formatted(date: .abbreviated, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 380, height: 320)
            }
        }
    }
}

private extension URL {
    var editorSyntaxMode: EditorSyntaxMode {
        switch pathExtension.lowercased() {
        case "bib":
            return .bibtex
        case "tex", "sty", "cls", "ltx":
            return .latex
        default:
            return .plain
        }
    }
}

private struct ReadOnlyTextPreviewPane: View {
    var preview: TextFilePreview

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.fileURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(preview.isTruncated ? .orange : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Open Externally") {
                    NSWorkspace.shared.open(preview.fileURL)
                }

                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([preview.fileURL])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            ScrollView([.vertical]) {
                Text(preview.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var summary: String {
        let total = ByteCountFormatter.string(fromByteCount: Int64(preview.byteCount), countStyle: .file)
        let shown = ByteCountFormatter.string(fromByteCount: Int64(preview.previewedByteCount), countStyle: .file)
        if preview.isTruncated {
            return "Read-only preview, \(shown) of \(total), \(preview.encodingDescription)"
        }
        return "Read-only, \(total), \(preview.encodingDescription)"
    }
}

private struct ImagePreviewPane: View {
    var fileURL: URL

    var body: some View {
        VStack(spacing: 14) {
            if let image = NSImage(contentsOf: fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Could not preview image.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Open Externally") {
                    NSWorkspace.shared.open(fileURL)
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct FilePlaceholderView: View {
    var icon: String
    var title: String
    var message: String
    var fileURL: URL?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let fileURL {
                HStack {
                    Button("Open Externally") {
                        NSWorkspace.shared.open(fileURL)
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct WelcomeDropView: View {
    var isDropTarget: Bool
    var statusMessage: String
    var openProject: () -> Void
    var importZip: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: compact(proxy) ? 12 : 18) {
                    TEXnologiaMarkView(size: compact(proxy) ? 62 : 84)

                    VStack(spacing: 5) {
                        Text("TEXnologia")
                            .font(.system(size: compact(proxy) ? 27 : 34, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }

                    VStack(spacing: 10) {
                        Button {
                            openProject()
                        } label: {
                            Label("Open Folder or File", systemImage: "folder.badge.plus")
                                .frame(minWidth: 210)
                        }
                        .controlSize(.large)

                        Button {
                            importZip()
                        } label: {
                            Label("Import Zip", systemImage: "archivebox")
                                .frame(minWidth: 210)
                        }
                        .controlSize(.large)
                    }

                    Text("Drag a LaTeX folder, .tex file, or .zip archive here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, compact(proxy) ? 16 : 28)
                .frame(minHeight: proxy.size.height, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 3)
                .padding(16)
        )
    }

    private func compact(_ proxy: GeometryProxy) -> Bool {
        proxy.size.height < 430 || proxy.size.width < 520
    }
}

private struct TEXnologiaMarkView: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.22, blue: 0.47), Color(red: 0.10, green: 0.58, blue: 0.50)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: size * 0.66, height: size * 0.66)
                .offset(y: size * 0.03)

            Capsule()
                .fill(Color(red: 0.96, green: 0.78, blue: 0.56))
                .frame(width: size * 0.07, height: size * 0.30)
                .rotationEffect(.degrees(44))
                .offset(x: -size * 0.20, y: size * 0.05)

            Capsule()
                .fill(Color(red: 0.96, green: 0.78, blue: 0.56))
                .frame(width: size * 0.07, height: size * 0.30)
                .rotationEffect(.degrees(-44))
                .offset(x: size * 0.20, y: size * 0.05)

            Circle()
                .fill(Color(red: 0.96, green: 0.78, blue: 0.56))
                .frame(width: size * 0.20, height: size * 0.20)
                .offset(y: size * 0.13)

            RoundedRectangle(cornerRadius: size * 0.05)
                .fill(Color(red: 0.05, green: 0.10, blue: 0.22))
                .frame(width: size * 0.28, height: size * 0.16)
                .offset(y: size * 0.20)

            RoundedRectangle(cornerRadius: size * 0.05)
                .fill(Color(red: 0.07, green: 0.14, blue: 0.30))
                .frame(width: size * 0.36, height: size * 0.24)
                .offset(y: size * 0.28)

            RoundedRectangle(cornerRadius: size * 0.055)
                .fill(Color(red: 0.97, green: 0.98, blue: 0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.055)
                        .stroke(Color(red: 0.92, green: 0.72, blue: 0.22), lineWidth: max(size * 0.018, 1))
                )
                .frame(width: size * 0.68, height: size * 0.25)
                .offset(y: -size * 0.12)

            Text("TEX")
                .font(.system(size: size * 0.13, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.07, green: 0.21, blue: 0.43))
                .offset(y: -size * 0.12)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.16), radius: size * 0.06, x: 0, y: size * 0.03)
        .accessibilityLabel("TEXnologia")
    }
}
