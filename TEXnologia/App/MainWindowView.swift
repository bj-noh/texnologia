import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct MainWindowView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isDropTarget = false
    @State private var issuePanelExpanded = false
    @State private var historyPresented = false
    @State private var rightPaneSplit = false
    @State private var editorPaneSplit = false

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
                .frame(height: issuePanelExpanded ? 280 : 44)
                .clipped()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            workspaceFooter
        }
        .background(FolioTheme.canvas)
        .foregroundStyle(FolioTheme.text)
        .tint(FolioTheme.accent)
        .accentColor(FolioTheme.accent)
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
                openProject: appModel.openProjectPanel,
                importZip: appModel.openZipPanel,
                createEmpty: appModel.createEmptyProjectPanel
            )

            HSplitView {
                ProjectSidebarView(
                    index: appModel.projectIndex,
                    rootURL: appModel.workspace?.rootURL,
                    mainFileURL: appModel.workspace?.mainFileURL,
                    outlineItems: appModel.currentEditorOutline,
                    hidesIntermediateArtifacts: appModel.settings.hidesIntermediateArtifacts,
                    saveStates: appModel.fileSaveStates,
                    selectedFileURL: $appModel.selectedFileURL,
                    onSelectFile: appModel.selectFile,
                    onMakeMainFile: appModel.setMainFile,
                    onMoveFile: appModel.moveExplorerSaveState,
                    onDeleteFile: appModel.removeExplorerSaveState,
                    onRefreshProject: appModel.refreshProject,
                    onExternalProjectChange: appModel.refreshProjectFromDisk,
                    onStatus: appModel.setStatus
                )
                .folioPane()
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 320)
                .layoutPriority(0)

                VStack(spacing: 0) {
                    EditorTabBar(
                        tabs: appModel.currentOpenEditorTabs,
                        activeURL: appModel.editorFileURL,
                        saveStates: appModel.fileSaveStates,
                        activate: appModel.activateEditorTab,
                        close: appModel.closeEditorTab
                    )
                    CenterPaneView(
                    presentation: appModel.selectedFilePresentation,
                    selectedFileURL: appModel.selectedFileURL,
                    editorFileURL: appModel.editorFileURL,
                    isEditorSaved: appModel.isEditorSaved,
                    isSplit: $editorPaneSplit,
                    text: Binding(
                        get: { appModel.editorText },
                        set: { appModel.updateEditorText($0) }
                    ),
                    settings: appModel.settings,
                    jump: appModel.editorJump
                    )
                }
                .folioPane()
                .frame(minWidth: 360, idealWidth: 620)
                .layoutPriority(1)

                HStack(spacing: 8) {
                    SyncNavigationControls()
                        .frame(width: 36)
                        .frame(maxHeight: .infinity)

                    RightPreviewPane(
                        focusedPane: $appModel.focusedPreviewPane,
                        primaryPresentation: appModel.primaryPreviewPresentation,
                        secondaryPresentation: appModel.secondaryPreviewPresentation,
                        isSplit: $rightPaneSplit
                    )
                    .folioPane()
                    .frame(minWidth: 280)
                }
                .frame(minWidth: 324, idealWidth: 524)
                .layoutPriority(1)

                if appModel.isChatPaneVisible {
                    ChatPaneView(
                        session: appModel.chatSession,
                        isPresented: Binding(
                            get: { appModel.isChatPaneVisible },
                            set: { appModel.isChatPaneVisible = $0 }
                        )
                    )
                    .folioPane()
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 520)
                    .layoutPriority(1)
                    .transition(.move(edge: .trailing))
                }
            }
            .background(SplitViewDividerHitExpander(extraHitAreaOnEachSide: 7))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var shouldShowIssueDock: Bool {
        appModel.buildIssues.contains { issue in
            issue.severity == .error || issue.severity == .warning
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 9) {
                TEXnologiaMarkView(size: 34)
                (Text("texnologia") + Text(".").foregroundColor(FolioTheme.accent))
                    .font(.system(size: 23, weight: .bold))
                    .tracking(-1)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("TEXnologia")

            Rectangle()
                .fill(FolioTheme.border)
                .frame(width: 1, height: 22)

            Text(appModel.workspace?.displayName ?? "LaTeX for Mac")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FolioTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                appModel.saveSelectedFileAndBuildIfNeeded()
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .buttonStyle(FolioIconButtonStyle())
            .help("Save")
            .accessibilityLabel("Save")
            .disabled(!appModel.canSaveEditorFile)

            Button {
                historyPresented.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(FolioIconButtonStyle())
            .help("History")
            .accessibilityLabel("History")
            .popover(isPresented: $historyPresented) {
                HistoryDiffPopover(
                    entries: appModel.history,
                    currentEditorText: appModel.editorText,
                    currentEditorFileURL: appModel.editorFileURL,
                    restore: { entry in
                        appModel.restoreHistoryEntry(entry)
                        historyPresented = false
                    }
                )
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appModel.toggleChatPane()
                }
            } label: {
                Image(systemName: appModel.isChatPaneVisible ? "sparkles.rectangle.stack.fill" : "sparkles")
                    .foregroundStyle(appModel.isChatPaneVisible ? FolioTheme.accent : FolioTheme.muted)
            }
            .buttonStyle(FolioIconButtonStyle())
            .help("AI Assistant")
            .accessibilityLabel("AI Assistant")

            CompileOptionsControl(
                settings: $appModel.settings,
                canCompile: appModel.workspace?.mainFileURL != nil && !appModel.isImporting && !appModel.isLoadingEditorFile,
                isCompiling: appModel.isCompiling,
                compilingFileName: appModel.compilingFileName,
                compile: appModel.compile,
                persistSettings: { appModel.updateSettings(appModel.settings) }
            )
        }
        .padding(.horizontal, 24)
        .frame(height: 66)
        .background(FolioTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FolioTheme.border)
                .frame(height: 1)
        }
    }

    private var workspaceFooter: some View {
        HStack(spacing: 8) {
            if !appModel.statusMessage.isEmpty {
                Circle().fill(FolioTheme.accent.opacity(0.65)).frame(width: 5, height: 5)
                Text(appModel.statusMessage)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(appModel.statusMessage)
            }
            Spacer(minLength: 20)
            if appModel.editorFileURL != nil {
                Text("\(appModel.editorText.components(separatedBy: .newlines).count) lines")
                Text("·")
                Text("\(appModel.editorText.count) characters")
                Rectangle().fill(FolioTheme.border).frame(width: 1, height: 10)
            }
            Text("LaTeX + AI")
                .tracking(0.3)
        }
        .font(.system(size: 10))
        .foregroundStyle(FolioTheme.muted)
        .padding(.horizontal, 24)
        .frame(height: 34)
        .background(FolioTheme.surface)
        .overlay(alignment: .top) { FolioTheme.border.frame(height: 1) }
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

struct CompileOptionsControl: View {
    @Binding var settings: AppSettings
    var canCompile: Bool
    var isCompiling: Bool
    var compilingFileName: String?
    var compile: () -> Void
    var persistSettings: () -> Void
    @State private var showsCompileSettings = false
    private let compileAccent = FolioTheme.accent

    var body: some View {
        HStack(spacing: 10) {
            if isCompiling {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FolioTheme.accent)
                        .frame(width: 14, height: 14)
                    Text("컴파일 중")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(FolioTheme.accent)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(FolioTheme.accentSoft, in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("컴파일 중")
                .help("Compiling \(compilingFileName ?? "your document"). New saves will compile next.")
                .transition(.opacity)
            }
            compileButtons
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeInOut(duration: 0.15), value: isCompiling)
    }

    private var compileButtons: some View {
        HStack(spacing: 0) {
            Button("Compile") {
                compile()
            }
            .keyboardShortcut("b", modifiers: [.command])
            .disabled(!canCompile || isCompiling)
            .help(compileHelpText)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(canCompile ? FolioTheme.onAccent : FolioTheme.muted)
            .frame(width: 82, height: 34)
            .background(canCompile ? compileAccent : Color.secondary.opacity(0.14))
            .opacity(isCompiling ? 0.55 : 1)

            Rectangle()
                .fill(Color.white.opacity(canCompile ? 0.30 : 0.08))
                .frame(width: 1, height: 16)

            Button {
                showsCompileSettings.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(canCompile ? FolioTheme.onAccent : FolioTheme.muted)
                    .frame(width: 26, height: 34)
                    .background(canCompile ? compileAccent : Color.secondary.opacity(0.14))
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
        .clipShape(RoundedRectangle(cornerRadius: 7))
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
    var openProject: () -> Void
    var importZip: () -> Void
    var createEmpty: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(sessions) { session in
                    let isActive = session.id == activeWorkspaceID
                    Button {
                        activate(session.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isActive ? "folder.fill" : "folder")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isActive ? FolioTheme.accent : .secondary)
                            Text(session.workspace.displayName)
                                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isActive ? FolioTheme.accentSoft : Color.clear)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(FolioTheme.accent.opacity(isActive ? 0.20 : 0), lineWidth: 1)
                        }
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

                Menu {
                    Button {
                        createEmpty()
                    } label: {
                        Label("New Empty Project…", systemImage: "doc.badge.plus")
                    }
                    Button {
                        openProject()
                    } label: {
                        Label("Open Folder or File…", systemImage: "folder.badge.plus")
                    }
                    Button {
                        importZip()
                    } label: {
                        Label("Import Zip…", systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .help("New Session")
                .accessibilityLabel("New Session")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.never)
        .background(FolioTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FolioTheme.border)
                .frame(height: 1)
        }
    }
}

private struct EditorTabBar: View {
    var tabs: [URL]
    var activeURL: URL?
    var saveStates: [URL: ExplorerSaveState]
    var activate: (URL) -> Void
    var close: (URL) -> Void

    var body: some View {
        if tabs.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(tabs, id: \.self) { url in
                        tab(for: url)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            .background(FolioTheme.sidebar)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FolioTheme.border)
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func tab(for url: URL) -> some View {
        let isActive = url == activeURL
        let state = saveStates[url] ?? .saved

        HStack(spacing: 5) {
            Circle()
                .fill(state == .dirty ? Color.orange : Color.green.opacity(0.85))
                .frame(width: 5, height: 5)
            Text(url.lastPathComponent)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
            Button {
                close(url)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close \(url.lastPathComponent)")
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isActive ? FolioTheme.accentSoft : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(FolioTheme.accent.opacity(isActive ? 0.20 : 0), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activate(url)
        }
        .help(url.path)
    }
}

private struct CenterPaneView: View {
    @EnvironmentObject private var appModel: AppModel
    var presentation: FilePresentation
    var selectedFileURL: URL?
    var editorFileURL: URL?
    var isEditorSaved: Bool
    @Binding var isSplit: Bool
    @Binding var text: String
    var settings: AppSettings
    var jump: EditorJump?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .onAppear { SyncTeXBridge.shared.editorFileURL = editorFileURL }
                .onChange(of: editorFileURL) { _, newValue in
                    SyncTeXBridge.shared.editorFileURL = newValue
                }
                .overlay(alignment: .top) {
                    if presentation == .text,
                       let pending = appModel.pendingEdit,
                       pending.fileURL == editorFileURL {
                        PendingEditReviewView(appModel: appModel, edit: pending)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: appModel.pendingEdit?.id)

            if presentation == .text {
                Button {
                    isSplit.toggle()
                } label: {
                    Image(systemName: isSplit ? "rectangle" : "rectangle.split.1x2")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .help(isSplit ? "Merge to single editor pane" : "Split editor pane")
                .accessibilityLabel(isSplit ? "Merge to single editor pane" : "Split editor pane")
                .background(FolioTheme.accentSoft, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 0.6)
                }
                .opacity(0.82)
                .padding(.top, 9)
                .padding(.trailing, 8)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            EditorStatusHeader(
                fileURL: statusFileURL,
                statusLabel: statusLabel,
                isSaved: presentation == .text && isEditorSaved,
                showsSaveIndicator: presentation == .text
            )

            ZStack {
                FolioTheme.surface
                    .ignoresSafeArea(.container, edges: .all)

                body(for: presentation)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func body(for presentation: FilePresentation) -> some View {
        switch presentation {
        case .text:
            if isSplit {
                VSplitView {
                    LaTeXEditorView(
                        text: $text,
                        settings: settings,
                        syntaxMode: editorFileURL?.editorSyntaxMode ?? .plain,
                        jump: jump
                    )
                    .frame(minHeight: 180)

                    LaTeXEditorView(
                        text: $text,
                        settings: settings,
                        syntaxMode: editorFileURL?.editorSyntaxMode ?? .plain,
                        jump: jump
                    )
                    .frame(minHeight: 180)
                }
            } else {
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
            PDFPaneView(documentURL: url, refreshID: appModel.pdfBuildRevision)
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

    private var statusFileURL: URL? {
        switch presentation {
        case .text: return editorFileURL
        case .readOnlyText(let preview): return preview.fileURL
        case .pdf(let url), .image(let url), .external(let url): return url
        case .none: return editorFileURL ?? selectedFileURL
        }
    }

    private var statusLabel: String? {
        switch presentation {
        case .text: return nil
        case .readOnlyText: return "Read-only preview"
        case .pdf: return "PDF preview"
        case .image: return "Image preview"
        case .external: return "External file"
        case .none: return "No file"
        }
    }
}

private struct EditorStatusHeader: View {
    var fileURL: URL?
    var statusLabel: String?
    var isSaved: Bool
    var showsSaveIndicator: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Text("SOURCE").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(FolioTheme.subtle)
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Text(fileURL?.lastPathComponent ?? "Untitled")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            if let statusLabel {
                Text(statusLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.10))
                    )
            }

            if showsSaveIndicator && isSaved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .help("Saved")
                    .accessibilityLabel("Saved")
            }

            Spacer()
        }
        .padding(.leading, 14)
        .padding(.trailing, 40)
        .frame(height: 40)
        .background(FolioTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FolioTheme.border)
                .frame(height: 1)
        }
        .animation(.easeInOut(duration: 0.12), value: isSaved)
    }

    private var iconName: String {
        if statusLabel?.contains("PDF") == true { return "doc.richtext" }
        if statusLabel?.contains("Image") == true { return "photo" }
        if statusLabel?.contains("Read-only") == true { return "doc.text.magnifyingglass" }
        if statusLabel?.contains("External") == true { return "doc" }
        if statusLabel?.contains("No file") == true { return "text.cursor" }
        return "doc.text"
    }
}

private struct RightPreviewPane: View {
    @EnvironmentObject private var appModel: AppModel
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
                Image(systemName: isSplit ? "rectangle" : "rectangle.split.1x2")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help(isSplit ? "Merge to single preview pane" : "Split preview pane")
            .accessibilityLabel(isSplit ? "Merge to single preview pane" : "Split preview pane")
            .background(FolioTheme.surface, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 0.6)
            }
            .opacity(0.82)
            .padding(.top, 49)
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
    @EnvironmentObject private var appModel: AppModel
    var paneID: PreviewPaneID
    var title: String
    var presentation: FilePresentation
    @Binding var focusedPane: PreviewPaneID

    private var isFocused: Bool {
        focusedPane == paneID
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isFocused ? FolioTheme.accent : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 11, weight: isFocused ? .semibold : .regular))
                    .foregroundStyle(isFocused ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(FolioTheme.surface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FolioTheme.border)
                    .frame(height: 1)
            }

            switch presentation {
            case .pdf(let url):
                PDFPaneView(documentURL: url, refreshID: appModel.pdfBuildRevision,
                            paneID: paneID, navigationTarget: appModel.pdfNavigationTarget,
                            onActivate: { focusedPane = paneID })
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
            Rectangle()
                .stroke(isFocused ? FolioTheme.accent.opacity(0.18) : Color.clear, lineWidth: 1)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .fixedSize(horizontal: false, vertical: false)
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
            .background(FolioTheme.surface)

            ScrollView([.vertical]) {
                Text(preview.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
            .background(FolioTheme.surface)
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
            .background(FolioTheme.surface)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .fixedSize(horizontal: false, vertical: false)
        .background(FolioTheme.surface)
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
        .background(FolioTheme.surface)
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

struct WelcomeDropView: View {
    var isDropTarget: Bool
    var statusMessage: String
    var openProject: () -> Void
    var importZip: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    HStack(spacing: 7) {
                        Circle().fill(FolioTheme.accent.opacity(0.65)).frame(width: 5, height: 5)
                        Text("A LITTLE SPACE FOR BIG IDEAS")
                            .tracking(2)
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(FolioTheme.accent)
                    .padding(.bottom, 18)

                    (Text("Room to think. ") + Text("Space to write.").foregroundColor(FolioTheme.accent))
                        .font(.system(size: proxy.size.width < 600 ? 27 : 35, weight: .semibold))
                        .tracking(-1.2)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)

                    Text("Write LaTeX, see your ideas take shape, and refine them with AI.\nYour projects, all together in a quiet workspace.")
                        .font(.system(size: 13))
                        .lineSpacing(6)
                        .foregroundStyle(FolioTheme.muted)
                        .multilineTextAlignment(.center)

                    WelcomeManuscriptPreview()
                        .padding(.top, 28)
                        .padding(.bottom, 20)

                    Button(action: openProject) {
                        VStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 21, weight: .light))
                                .foregroundStyle(FolioTheme.accent)
                                .frame(width: 46, height: 46)
                                .background(FolioTheme.accentSoft, in: RoundedRectangle(cornerRadius: 13))
                            Text("Bring your next idea here")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(FolioTheme.text)
                            Text("Drop a LaTeX folder, .tex or .bib file, or .zip archive")
                                .font(.system(size: 11))
                                .foregroundStyle(FolioTheme.muted)
                            HStack(spacing: 6) {
                                Text("Open Folder or File")
                                Image(systemName: "arrow.right")
                                Text("⌘O").font(.system(size: 10, design: .monospaced))
                                    .padding(.leading, 8)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FolioTheme.accent)
                            .padding(.top, 3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(isDropTarget ? FolioTheme.accentSoft : FolioTheme.surface.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(FolioTheme.accent.opacity(isDropTarget ? 0.9 : 0.32), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Folder or File")

                    Button(action: importZip) {
                        Label("Import Zip Archive", systemImage: "archivebox")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FolioTheme.accent)
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 5)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 24) { features }
                        VStack(spacing: 10) { features }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(FolioTheme.muted)
                    .padding(.top, 10)

                    Text("Local files. Thoughtful tools. Your own AI provider.")
                        .font(.system(size: 10))
                        .foregroundStyle(FolioTheme.subtle)
                        .padding(.top, 24)
                }
                .frame(maxWidth: 654)
                .padding(.horizontal, 28)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollIndicators(.automatic)
        }
        .background {
            RadialGradient(colors: [FolioTheme.accentSoft.opacity(0.55), FolioTheme.canvas], center: .init(x: 0.5, y: 0.35), startRadius: 0, endRadius: 540)
        }
    }

    @ViewBuilder
    private var features: some View {
        Label("Native editing", systemImage: "checkmark")
        Label("Local PDF compilation", systemImage: "checkmark")
        Label("AI, with your approval", systemImage: "checkmark")
    }
}

private struct WelcomeManuscriptPreview: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Label("WRITE", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 9, weight: .medium)).tracking(1.5)
                    .foregroundStyle(FolioTheme.subtle)
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: #"\section{A world of possibility}"#).foregroundStyle(FolioTheme.accent)
                    Text("Every idea begins with a line.")
                    Text(verbatim: #"\[ E = mc^2 \]"#).foregroundStyle(FolioTheme.accent)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(FolioTheme.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 152, alignment: .leading)
            .background(FolioTheme.sidebar)

            FolioTheme.border.frame(width: 1)

            VStack(alignment: .leading, spacing: 12) {
                Label("PREVIEW", systemImage: "book")
                    .font(.system(size: 9, weight: .medium)).tracking(1.5)
                    .foregroundStyle(FolioTheme.subtle)
                Text("A world of possibility")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(FolioTheme.text)
                Text("Every idea begins with a line.")
                    .font(.system(size: 10)).foregroundStyle(FolioTheme.muted)
                Text("E = mc²")
                    .font(.system(size: 20, design: .serif)).italic()
                    .foregroundStyle(FolioTheme.accent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 152, alignment: .leading)
            .background(FolioTheme.surface)
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(FolioTheme.border, lineWidth: 1) }
        .overlay {
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(FolioTheme.subtle)
                .frame(width: 28, height: 28)
                .background(FolioTheme.surface, in: Circle())
                .overlay { Circle().strokeBorder(FolioTheme.border, lineWidth: 1) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example: LaTeX source and its typeset preview")
    }
}

private struct TEXnologiaMarkView: View {
    var size: CGFloat
    var body: some View { FolioDocumentMark(size: size).accessibilityLabel("TEXnologia") }
}

private extension View {
    func folioPane() -> some View {
        self
            .background(FolioTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(FolioTheme.border, lineWidth: 1).allowsHitTesting(false) }
            .padding(.horizontal, 4)
    }
}

private struct SyncNavigationControls: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 10) {
            SyncArrowButton(systemName: "arrow.right", help: "원문 → 미리보기: 에디터 커서 위치로 이동") {
                appModel.syncTeXForward()
            }
            .disabled(appModel.editorFileURL == nil || appModel.pdfDocumentURL == nil || appModel.isLoadingEditorFile)

            SyncArrowButton(systemName: "arrow.left", help: "미리보기 → 원문: PDF에서 클릭한 위치로 이동") {
                appModel.syncTeXReverse()
            }
            .disabled(!hasPDFPreview)
        }
    }

    private var hasPDFPreview: Bool {
        let presentation = appModel.focusedPreviewPane == .primary
            ? appModel.primaryPreviewPresentation : appModel.secondaryPreviewPresentation
        if case .pdf = presentation { return true }
        return false
    }
}

private struct SyncArrowButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FolioTheme.accent)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(FolioTheme.surface)
                )
                .overlay(
                    Circle()
                        .stroke(FolioTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
