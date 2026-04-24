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

            if shouldShowIssueDock {
                IssueDockView(
                    issues: appModel.buildIssues,
                    isExpanded: $issuePanelExpanded,
                    onSelect: appModel.jumpToIssue
                )
                .frame(height: issuePanelExpanded ? 260 : 36)
                .clipped()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(appModel.settings.appearance.colorScheme)
        .animation(.easeInOut(duration: 0.16), value: issuePanelExpanded)
        .animation(.easeInOut(duration: 0.16), value: shouldShowIssueDock)
        .onChange(of: appModel.buildIssues) { _, issues in
            if issues.isEmpty {
                issuePanelExpanded = false
            }
        }
    }

    private var workspaceLayout: some View {
        VStack(spacing: 0) {
            SessionTabBar(
                sessions: appModel.sessions,
                activeWorkspaceID: appModel.workspace?.id,
                activate: appModel.activateSession,
                close: appModel.closeSession,
                newSession: appModel.openProjectPanel
            )

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
                    onExternalProjectChange: appModel.refreshProjectFromDisk,
                    onStatus: appModel.setStatus
                )
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

                CenterPaneView(
                    presentation: appModel.selectedFilePresentation,
                    selectedFileURL: appModel.selectedFileURL,
                    editorFileURL: appModel.editorFileURL,
                    isEditorSaved: appModel.isEditorSaved,
                    text: $appModel.editorText,
                    settings: appModel.settings,
                    jump: appModel.editorJump
                )
                .frame(minWidth: 420)

                RightPreviewPane(
                    focusedPane: $appModel.focusedPreviewPane,
                    primaryPresentation: appModel.primaryPreviewPresentation,
                    secondaryPresentation: appModel.secondaryPreviewPresentation,
                    isSplit: $rightPaneSplit
                )
                    .frame(minWidth: 360)
            }
        }
    }

    private var shouldShowIssueDock: Bool {
        appModel.buildIssues.contains { issue in
            issue.severity == .error || issue.severity == .warning
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

            Button {
                historyPresented.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("History")
            .accessibilityLabel("History")
            .popover(isPresented: $historyPresented) {
                HistoryPopover(entries: appModel.history, restore: appModel.restoreHistoryEntry)
            }

            Button {
                appModel.exportFocusedPDF()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Export PDF")
            .accessibilityLabel("Export PDF")
            .disabled(!appModel.canExportFocusedPDF)

            CompileOptionsControl(
                settings: $appModel.settings,
                canCompile: appModel.workspace?.mainFileURL != nil && !appModel.isImporting,
                compile: appModel.compile,
                persistSettings: { appModel.updateSettings(appModel.settings) }
            )
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

private struct CompileOptionsControl: View {
    @Binding var settings: AppSettings
    var canCompile: Bool
    var compile: () -> Void
    var persistSettings: () -> Void
    @State private var showsCompileSettings = false
    private let compileBlue = Color(red: 0.20, green: 0.36, blue: 0.58)

    var body: some View {
        HStack(spacing: 0) {
            Button("Compile") {
                compile()
            }
            .keyboardShortcut("b", modifiers: [.command])
            .disabled(!canCompile)
            .help(compileHelpText)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(canCompile ? Color.white : Color.secondary)
            .frame(width: 82, height: 24)
            .background(canCompile ? compileBlue : Color.secondary.opacity(0.14))

            Rectangle()
                .fill(Color.white.opacity(canCompile ? 0.30 : 0.08))
                .frame(width: 1, height: 16)

            Button {
                showsCompileSettings.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(canCompile ? Color.white : Color.secondary)
                    .frame(width: 26, height: 24)
                    .background(canCompile ? compileBlue : Color.secondary.opacity(0.14))
            }
            .buttonStyle(.plain)
            .help("Compile Settings")
            .accessibilityLabel("Compile Settings")
            .popover(isPresented: $showsCompileSettings, arrowEdge: .top) {
                CompileSettingsPopover(
                    settings: $settings,
                    persistSettings: persistSettings
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .frame(width: 109)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var currentSummary: String {
        "\(settings.defaultEngine.displayName) · TeX Live \(settings.toolchainYear.displayName)"
    }

    private var compileHelpText: String {
        "Compile with \(settings.defaultEngine.displayName), TeX Live \(settings.toolchainYear.displayName)"
    }
}

private struct CompileSettingsPopover: View {
    @Binding var settings: AppSettings
    var persistSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(settings.defaultEngine.displayName) · TeX Live \(settings.toolchainYear.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Engine")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(LatexEngine.allCases, id: \.self) { engine in
                    optionButton(
                        title: engine.displayName,
                        isSelected: settings.defaultEngine == engine
                    ) {
                        settings.defaultEngine = engine
                        persistSettings()
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("TeX Live Year")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(TexToolchainYear.allCases, id: \.self) { year in
                    optionButton(
                        title: year.displayName,
                        isSelected: settings.toolchainYear == year
                    ) {
                        settings.toolchainYear = year
                        persistSettings()
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 190)
    }

    private func optionButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SessionTabBar: View {
    var sessions: [WorkspaceSession]
    var activeWorkspaceID: WorkspaceID?
    var activate: (WorkspaceID) -> Void
    var close: (WorkspaceID) -> Void
    var newSession: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(sessions) { session in
                    Button {
                        activate(session.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: session.id == activeWorkspaceID ? "shippingbox.fill" : "shippingbox")
                                .font(.caption)
                            Text(session.workspace.displayName)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(session.id == activeWorkspaceID ? Color.accentColor.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(session.workspace.rootURL.path)
                    .contextMenu {
                        Button("Close Session") {
                            close(session.id)
                        }
                        .help("Only closes this app session. Files on disk are not changed.")
                    }
                }

                Button {
                    newSession()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("New Session")
                .accessibilityLabel("New Session")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .scrollIndicators(.never)
        .background(.bar)
    }
}

private struct CenterPaneView: View {
    var presentation: FilePresentation
    var selectedFileURL: URL?
    var editorFileURL: URL?
    var isEditorSaved: Bool
    @Binding var text: String
    var settings: AppSettings
    var jump: EditorJump?

    var body: some View {
        Group {
            switch presentation {
            case .text:
                VStack(spacing: 0) {
                    EditorStatusHeader(
                        fileURL: editorFileURL,
                        isSaved: isEditorSaved
                    )

                    LaTeXEditorView(
                        text: $text,
                        settings: settings,
                        syntaxMode: editorFileURL?.editorSyntaxMode ?? .plain,
                        jump: jump
                    )
                }
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
                    fileURL: editorFileURL ?? selectedFileURL
                )
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .fixedSize(horizontal: false, vertical: false)
    }
}

private struct EditorStatusHeader: View {
    var fileURL: URL?
    var isSaved: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(fileURL?.lastPathComponent ?? "Untitled")
                .font(.caption)
                .lineLimit(1)

            if isSaved {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .help("Saved")
                    .accessibilityLabel("Saved")
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.bar)
        .animation(.easeInOut(duration: 0.12), value: isSaved)
    }
}

private struct RightPreviewPane: View {
    @Binding var focusedPane: PreviewPaneID
    var primaryPresentation: FilePresentation
    var secondaryPresentation: FilePresentation
    @Binding var isSplit: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            previewContent

            Button {
                isSplit.toggle()
            } label: {
                Image(systemName: isSplit ? "rectangle.split.1x2" : "rectangle.split.2x1")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help(isSplit ? "Use single preview pane" : "Split preview pane")
            .accessibilityLabel(isSplit ? "Use single preview pane" : "Split preview pane")
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 0.6)
            }
            .opacity(0.82)
            .padding(.top, 32)
            .padding(.trailing, 8)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .fixedSize(horizontal: false, vertical: false)
    }

    @ViewBuilder
    private var previewContent: some View {
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
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .fixedSize(horizontal: false, vertical: false)
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
    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: max(proxy.size.width - 40, 0),
                                height: max(proxy.size.height - 40, 0)
                            )
                            .clipped()
                    } else if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(
                                width: max(proxy.size.width - 40, 0),
                                height: max(proxy.size.height - 40, 0)
                            )
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary)
                            Text("Could not preview image.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(
                            width: max(proxy.size.width - 40, 0),
                            height: max(proxy.size.height - 40, 0)
                        )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)

            HStack {
                Button("Open Externally") {
                    NSWorkspace.shared.open(fileURL)
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .fixedSize(horizontal: false, vertical: false)
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: fileURL) {
            image = nil
            isLoading = true
            let imageData = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: fileURL)
            }.value
            image = imageData.flatMap(NSImage.init(data:))
            isLoading = false
        }
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
