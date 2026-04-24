import AppKit
import CoreFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var workspace: Workspace?
    @Published var sessions: [WorkspaceSession] = []
    @Published var selectedFileURL: URL?
    @Published var editorFileURL: URL?
    @Published var editorText: String = ""
    @Published var selectedFilePresentation: FilePresentation = .none
    @Published var projectIndex: ProjectIndex = .empty
    @Published var buildIssues: [BuildIssue] = []
    @Published var pdfDocumentURL: URL?
    @Published var focusedPreviewPane: PreviewPaneID = .primary
    @Published var primaryPreviewPresentation: FilePresentation = .none
    @Published var secondaryPreviewPresentation: FilePresentation = .none
    @Published var editorJump: EditorJump?
    @Published var settings: AppSettings = .default
    @Published var statusMessage: String = "Drop a LaTeX folder, .tex file, or .zip archive to begin."
    @Published var isImporting: Bool = false
    @Published var history: [HistoryEntry] = []
    @Published var fileSaveStates: [URL: ExplorerSaveState] = [:]
    @Published private var savedEditorFileURL: URL?
    @Published private var savedEditorText: String = ""

    private let indexer = ProjectIndexer()
    private let buildService = LatexBuildService()
    private var selectedFileEncoding: String.Encoding = .utf8

    var canExportFocusedPDF: Bool {
        focusedPDFURL != nil
    }

    var canSaveEditorFile: Bool {
        editorFileURL != nil && selectedFilePresentation == .text
    }

    var isEditorSaved: Bool {
        guard selectedFilePresentation == .text, let editorFileURL else { return false }
        return savedEditorFileURL == editorFileURL && savedEditorText == editorText
    }

    var editorSaveState: ExplorerSaveState? {
        guard canSaveEditorFile else { return nil }
        return isEditorSaved ? .saved : .dirty
    }

    var currentEditorOutline: [OutlineItem] {
        guard selectedFilePresentation == .text, let editorFileURL else { return [] }
        return indexer.outlineItems(in: editorText, fileURL: editorFileURL)
    }

    func updateEditorText(_ newText: String) {
        editorText = newText
        guard selectedFilePresentation == .text, let editorFileURL else { return }

        if savedEditorFileURL == editorFileURL, savedEditorText == newText {
            if fileSaveStates[editorFileURL] != nil {
                fileSaveStates[editorFileURL] = .saved
            }
        } else {
            fileSaveStates[editorFileURL] = .dirty
        }
    }

    init() {
        settings = SettingsStore.loadMigratingIfNeeded()
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        SettingsStore.save(newSettings)
    }

    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .texSource, .zipArchive]
        panel.message = "Choose a LaTeX project folder, a .tex file, or a .zip archive."
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openProjectResource(at: url)
    }

    func openZipPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zipArchive]
        panel.message = "Choose a zip archive containing a LaTeX project."
        panel.prompt = "Import Zip"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openProjectResource(at: url)
    }

    func openProjectResource(at url: URL) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            openProject(at: url)
        } else if url.pathExtension.lowercased() == "zip" {
            importZipArchive(at: url)
        } else if url.pathExtension.lowercased() == "tex" {
            openProject(at: url.deletingLastPathComponent(), preferredMainFile: url)
        } else {
            statusMessage = "TEXnologia can open folders, .tex files, and .zip archives."
        }
    }

    func openProject(at rootURL: URL, preferredMainFile: URL? = nil) {
        let displayName = rootURL.lastPathComponent
        let detectedRoot = preferredMainFile ?? indexer.detectRootFile(in: rootURL)
        let workspaceID = sessions.first { $0.workspace.rootURL.standardizedFileURL == rootURL.standardizedFileURL }?.workspace.id ?? WorkspaceID()

        let nextWorkspace = Workspace(
            id: workspaceID,
            rootURL: rootURL,
            mainFileURL: detectedRoot,
            displayName: displayName
        )
        let nextIndex = indexer.indexProject(rootURL: rootURL, mainFileURL: detectedRoot)

        workspace = nextWorkspace
        projectIndex = nextIndex
        upsertSession(workspace: nextWorkspace, index: nextIndex)
        selectedFileURL = detectedRoot
        editorFileURL = detectedRoot
        selectedFilePresentation = detectedRoot == nil ? .none : .text
        loadSelectedFile()
        statusMessage = detectedRoot == nil
            ? "Opened \(displayName), but no root .tex file was detected yet."
            : "Opened \(displayName)."
    }

    func loadSelectedFile() {
        guard let selectedFileURL else {
            editorFileURL = nil
            editorText = ""
            markEditorClean(fileURL: nil, text: "")
            selectedFilePresentation = .none
            return
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: selectedFileURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return
        }

        if selectedFileURL.isGeneratedTextPreviewFile {
            loadReadOnlyPreview(for: selectedFileURL)
            return
        }

        guard selectedFileURL.isEditableTextFile else {
            let presentation = selectedFileURL.presentation
            if case .image = presentation {
                prepareEditorForPreviewSelection()
                showInFocusedPreview(presentation)
                statusMessage = "Previewing \(selectedFileURL.lastPathComponent). Editor kept \(editorFileURL?.lastPathComponent ?? "current source")."
                return
            }
            if case .pdf(let url) = presentation {
                prepareEditorForPreviewSelection()
                pdfDocumentURL = url
                showInFocusedPreview(presentation)
                statusMessage = "Opened \(url.lastPathComponent) in the focused preview pane. Editor kept \(editorFileURL?.lastPathComponent ?? "current source")."
                return
            }

            editorFileURL = nil
            editorText = ""
            markEditorClean(fileURL: nil, text: "")
            selectedFilePresentation = presentation
            showInFocusedPreview(presentation)
            statusMessage = "Selected \(selectedFileURL.lastPathComponent)."
            return
        }

        do {
            let loaded = try TextFileLoader.loadEditable(url: selectedFileURL)
            editorFileURL = selectedFileURL
            editorText = selectedFileURL.pathExtension.lowercased() == "json"
                ? TextFileLoader.prettyPrintedJSONIfPossible(loaded.text)
                : loaded.text
            selectedFileEncoding = loaded.encoding
            selectedFilePresentation = .text
            markEditorClean(fileURL: selectedFileURL, text: editorText)
            fileSaveStates[selectedFileURL] = .saved
            statusMessage = "Opened \(selectedFileURL.lastPathComponent)."
        } catch TextFileLoader.LoadError.fileTooLarge {
            loadReadOnlyPreview(for: selectedFileURL)
        } catch {
            editorFileURL = nil
            editorText = ""
            markEditorClean(fileURL: nil, text: "")
            selectedFilePresentation = .external(selectedFileURL)
            statusMessage = "Could not read \(selectedFileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func selectFile(_ url: URL) {
        activateSession(containing: url)
        selectedFileURL = url
        loadSelectedFile()
    }

    func activateSession(_ id: WorkspaceID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        workspace = session.workspace
        projectIndex = session.index
        statusMessage = "Activated \(session.workspace.displayName)."
    }

    func closeSession(_ id: WorkspaceID) {
        guard let closingIndex = sessions.firstIndex(where: { $0.id == id }) else { return }
        let closedSession = sessions.remove(at: closingIndex)

        guard workspace?.id == id else {
            statusMessage = "Closed \(closedSession.workspace.displayName) session."
            return
        }

        if sessions.isEmpty {
            workspace = nil
            projectIndex = .empty
            selectedFileURL = nil
            editorFileURL = nil
            editorText = ""
            markEditorClean(fileURL: nil, text: "")
            selectedFilePresentation = .none
            buildIssues = []
            pdfDocumentURL = nil
            primaryPreviewPresentation = .none
            secondaryPreviewPresentation = .none
            statusMessage = "Closed \(closedSession.workspace.displayName) session."
            return
        }

        let nextIndex = min(closingIndex, sessions.count - 1)
        let nextSession = sessions[nextIndex]
        workspace = nextSession.workspace
        projectIndex = nextSession.index
        selectedFileURL = nextSession.workspace.mainFileURL
        editorFileURL = nextSession.workspace.mainFileURL
        selectedFilePresentation = selectedFileURL == nil ? .none : .text
        loadSelectedFile()
        statusMessage = "Closed \(closedSession.workspace.displayName) session."
    }

    private func activateSession(containing url: URL) {
        guard let session = sessions.first(where: { url.path == $0.workspace.rootURL.path || url.path.hasPrefix($0.workspace.rootURL.path + "/") }) else { return }
        workspace = session.workspace
        projectIndex = session.index
    }

    func jumpToIssue(_ issue: BuildIssue) {
        guard let location = issue.location else {
            statusMessage = issue.message
            return
        }

        selectedFileURL = location.fileURL
        editorFileURL = location.fileURL
        selectedFilePresentation = .text
        loadSelectedFile()
        editorJump = EditorJump(location: location)
        statusMessage = "\(location.fileURL.lastPathComponent):\(location.line) - \(issue.message)"
    }

    func refreshProject(preferredMainFile: URL? = nil, preferredSelection: URL? = nil) {
        guard var workspace else { return }

        let fileManager = FileManager.default
        let existingMain = workspace.mainFileURL.flatMap { fileManager.fileExists(atPath: $0.path) ? $0 : nil }
        let mainFile = preferredMainFile ?? existingMain ?? indexer.detectRootFile(in: workspace.rootURL)

        workspace.mainFileURL = mainFile
        self.workspace = workspace
        projectIndex = indexer.indexProject(rootURL: workspace.rootURL, mainFileURL: mainFile)
        upsertSession(workspace: workspace, index: projectIndex)
        pruneMissingExplorerSaveStates()

        if let preferredSelection, fileManager.fileExists(atPath: preferredSelection.path) {
            selectedFileURL = preferredSelection
        } else if let selectedFileURL, fileManager.fileExists(atPath: selectedFileURL.path) {
            self.selectedFileURL = selectedFileURL
        } else if let editorFileURL, fileManager.fileExists(atPath: editorFileURL.path) {
            selectedFileURL = editorFileURL
        } else {
            selectedFileURL = mainFile
        }

        loadSelectedFile()
    }

    func refreshProjectFromDisk() {
        guard var workspace else { return }

        let fileManager = FileManager.default
        let existingMain = workspace.mainFileURL.flatMap { fileManager.fileExists(atPath: $0.path) ? $0 : nil }
        let mainFile = existingMain ?? indexer.detectRootFile(in: workspace.rootURL)

        workspace.mainFileURL = mainFile
        self.workspace = workspace
        projectIndex = indexer.indexProject(rootURL: workspace.rootURL, mainFileURL: mainFile)
        upsertSession(workspace: workspace, index: projectIndex)
        pruneMissingExplorerSaveStates()

        if let selectedFileURL, !fileManager.fileExists(atPath: selectedFileURL.path) {
            self.selectedFileURL = editorFileURL.flatMap { fileManager.fileExists(atPath: $0.path) ? $0 : nil } ?? mainFile
        }
    }

    func moveExplorerSaveState(from sourceURL: URL, to destinationURL: URL) {
        fileSaveStates = Dictionary(
            uniqueKeysWithValues: fileSaveStates.map { url, state in
                (movedURL(url, from: sourceURL, to: destinationURL) ?? url, state)
            }
        )

        if let selectedFileURL, let moved = movedURL(selectedFileURL, from: sourceURL, to: destinationURL) {
            self.selectedFileURL = moved
        }
        if let editorFileURL, let moved = movedURL(editorFileURL, from: sourceURL, to: destinationURL) {
            self.editorFileURL = moved
        }
        if let savedEditorFileURL, let moved = movedURL(savedEditorFileURL, from: sourceURL, to: destinationURL) {
            self.savedEditorFileURL = moved
        }
    }

    func removeExplorerSaveState(for deletedURL: URL) {
        fileSaveStates = fileSaveStates.filter { url, _ in
            !url.isSameOrDescendant(of: deletedURL)
        }

        if selectedFileURL?.isSameOrDescendant(of: deletedURL) == true {
            selectedFileURL = nil
        }
        if editorFileURL?.isSameOrDescendant(of: deletedURL) == true {
            editorFileURL = nil
            editorText = ""
            selectedFilePresentation = .none
            markEditorClean(fileURL: nil, text: "")
        }
    }

    func setStatus(_ message: String) {
        statusMessage = message
    }

    func saveSelectedFile() {
        guard let editorFileURL else { return }
        guard selectedFilePresentation == .text else { return }
        do {
            captureHistorySnapshot(reason: "Before save")
            try editorText.write(to: editorFileURL, atomically: true, encoding: selectedFileEncoding)
            markEditorClean(fileURL: editorFileURL, text: editorText)
            fileSaveStates[editorFileURL] = .saved
            statusMessage = "Saved \(editorFileURL.lastPathComponent)."
        } catch {
            statusMessage = "Could not save \(editorFileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func setMainFile(_ url: URL) {
        guard url.pathExtension.lowercased() == "tex" else {
            statusMessage = "Only .tex files can be used as the main file."
            return
        }

        activateSession(containing: url)
        guard var workspace else { return }
        workspace.mainFileURL = url
        self.workspace = workspace
        projectIndex = indexer.indexProject(rootURL: workspace.rootURL, mainFileURL: url)
        upsertSession(workspace: workspace, index: projectIndex)
        statusMessage = "\(url.lastPathComponent) is now the main file for \(workspace.displayName)."
    }

    func restoreHistoryEntry(_ entry: HistoryEntry) {
        selectedFileURL = entry.fileURL
        editorFileURL = entry.fileURL
        selectedFilePresentation = .text
        selectedFileEncoding = .utf8
        editorText = entry.text
        fileSaveStates[entry.fileURL] = .dirty
        activateSession(containing: entry.fileURL)
        statusMessage = "Restored \(entry.fileName) from history."
    }

    private func loadReadOnlyPreview(for url: URL) {
        do {
            let preview = try TextFileLoader.loadPreview(url: url)
            editorFileURL = nil
            editorText = ""
            markEditorClean(fileURL: nil, text: "")
            selectedFilePresentation = .readOnlyText(preview)
            let prefix = preview.isTruncated ? "Previewing" : "Opened"
            statusMessage = "\(prefix) \(url.lastPathComponent) read-only."
        } catch {
            editorFileURL = nil
            editorText = ""
            markEditorClean(fileURL: nil, text: "")
            selectedFilePresentation = .external(url)
            statusMessage = "Could not preview \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func saveSelectedFileAndBuildIfNeeded() {
        saveSelectedFile()
        if settings.autoBuildOnSave {
            compile()
        }
    }

    func build() {
        compile()
    }

    func compile() {
        guard let workspace, let mainFileURL = workspace.mainFileURL else { return }
        saveSelectedFile()
        statusMessage = "Compiling \(mainFileURL.lastPathComponent)..."

        Task {
            let configuration = BuildConfiguration.default(
                rootFile: mainFileURL,
                engine: settings.defaultEngine,
                toolchainYear: settings.toolchainYear,
                shellEscape: settings.shellEscapeEnabled
            )
            let result = await buildService.build(configuration: configuration)
            buildIssues = result.issues
            pdfDocumentURL = result.pdfURL
            if let pdfURL = result.pdfURL {
                showInFocusedPreview(.pdf(pdfURL))
            }
            statusMessage = result.succeeded
                ? "Compile succeeded."
                : "Compile failed with \(result.issues.count) issue(s)."
        }
    }

    func exportFocusedPDF() {
        guard let sourceURL = focusedPDFURL else {
            statusMessage = "No compiled PDF is available to export yet."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.message = "Export the PDF shown in the focused preview pane."
        panel.prompt = "Export PDF"

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        do {
            let pdfData = try Data(contentsOf: sourceURL)
            try pdfData.write(to: destinationURL, options: .atomic)
            statusMessage = "Exported \(destinationURL.lastPathComponent)."
        } catch {
            statusMessage = "Could not export PDF: \(error.localizedDescription)"
        }
    }

    private func pruneMissingExplorerSaveStates() {
        let fileManager = FileManager.default
        fileSaveStates = fileSaveStates.filter { url, _ in
            fileManager.fileExists(atPath: url.path)
        }
    }

    private func movedURL(_ url: URL, from sourceURL: URL, to destinationURL: URL) -> URL? {
        if url == sourceURL {
            return destinationURL
        }

        let sourcePath = sourceURL.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        guard urlPath.hasPrefix(sourcePath + "/") else { return nil }

        let relativePath = String(urlPath.dropFirst(sourcePath.count + 1))
        return destinationURL.appendingPathComponent(relativePath)
    }

    private func showInFocusedPreview(_ presentation: FilePresentation) {
        switch focusedPreviewPane {
        case .primary:
            primaryPreviewPresentation = presentation
        case .secondary:
            secondaryPreviewPresentation = presentation
        }
    }

    private func prepareEditorForPreviewSelection() {
        guard let workspace else { return }
        if selectedFilePresentation == .text,
           let editorFileURL,
           editorFileURL.isInsideOrEqual(to: workspace.rootURL) {
            return
        }

        guard let mainFileURL = workspace.mainFileURL, mainFileURL.isEditableTextFile else { return }

        do {
            let loaded = try TextFileLoader.loadEditable(url: mainFileURL)
            editorFileURL = mainFileURL
            editorText = mainFileURL.pathExtension.lowercased() == "json"
                ? TextFileLoader.prettyPrintedJSONIfPossible(loaded.text)
                : loaded.text
            selectedFileEncoding = loaded.encoding
            selectedFilePresentation = .text
            markEditorClean(fileURL: mainFileURL, text: editorText)
        } catch {
            // Keep the current editor state; preview selection should never blank the editor.
        }
    }

    private var focusedPDFURL: URL? {
        let focusedPresentation: FilePresentation
        if focusedPreviewPane == .primary {
            focusedPresentation = primaryPreviewPresentation
        } else {
            focusedPresentation = secondaryPreviewPresentation
        }

        if case .pdf(let url) = focusedPresentation {
            return url
        }

        return pdfDocumentURL
    }

    private func captureHistorySnapshot(reason: String) {
        guard let editorFileURL, selectedFilePresentation == .text else { return }
        guard history.first?.fileURL != editorFileURL || history.first?.text != editorText else { return }
        history.insert(HistoryEntry(
            fileURL: editorFileURL,
            fileName: editorFileURL.lastPathComponent,
            text: editorText,
            createdAt: Date(),
            reason: reason
        ), at: 0)
        if history.count > 80 {
            history.removeLast(history.count - 80)
        }
    }

    private func upsertSession(workspace: Workspace, index: ProjectIndex) {
        let session = WorkspaceSession(workspace: workspace, index: index)
        if let existing = sessions.firstIndex(where: { $0.id == workspace.id || $0.workspace.rootURL == workspace.rootURL }) {
            sessions[existing] = session
        } else {
            sessions.append(session)
        }
    }

    private func markEditorClean(fileURL: URL?, text: String) {
        savedEditorFileURL = fileURL
        savedEditorText = text
    }

    private func importZipArchive(at zipURL: URL) {
        isImporting = true
        statusMessage = "Importing \(zipURL.lastPathComponent)..."

        Task {
            do {
                let destination = try makeImportDestination(for: zipURL)
                try await unzip(zipURL: zipURL, destination: destination)
                let projectRoot = bestProjectRoot(in: destination)
                openProject(at: projectRoot)
                statusMessage = "Imported \(zipURL.lastPathComponent)."
            } catch {
                statusMessage = "Could not import zip: \(error.localizedDescription)"
            }
            isImporting = false
        }
    }

    private func makeImportDestination(for zipURL: URL) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let importsRoot = support
            .appendingPathComponent("TEXnologia", isDirectory: true)
            .appendingPathComponent("ImportedProjects", isDirectory: true)

        try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)

        let baseName = zipURL.deletingPathExtension().lastPathComponent
        let folderName = "\(baseName)-\(UUID().uuidString.prefix(8))"
        let destination = importsRoot.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        return destination
    }

    private func unzip(zipURL: URL, destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", zipURL.path, destination.path]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "ditto failed"
                throw NSError(
                    domain: "TEXnologia.ZipImport",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: output]
                )
            }
        }.value
    }

    private func bestProjectRoot(in extractedRoot: URL) -> URL {
        if indexer.detectRootFile(in: extractedRoot) != nil {
            return extractedRoot
        }

        let childDirectories = (try? FileManager.default.contentsOfDirectory(
            at: extractedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter { url in
            ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
        } ?? []

        if childDirectories.count == 1,
           indexer.detectRootFile(in: childDirectories[0]) != nil {
            return childDirectories[0]
        }

        return extractedRoot
    }
}

private extension UTType {
    static let texSource = UTType(filenameExtension: "tex") ?? .plainText
    static let zipArchive = UTType(filenameExtension: "zip") ?? .archive
}

private extension URL {
    func isInsideOrEqual(to rootURL: URL) -> Bool {
        path == rootURL.path || path.hasPrefix(rootURL.path + "/")
    }

    func isSameOrDescendant(of rootURL: URL) -> Bool {
        standardizedFileURL.path == rootURL.standardizedFileURL.path
            || standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/")
    }

    var isEditableTextFile: Bool {
        let editableExtensions: Set<String> = [
            "tex", "bib", "sty", "cls", "ltx",
            "txt", "md", "markdown",
            "json", "jsonc", "yaml", "yml", "toml", "xml", "plist",
            "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx",
            "js", "jsx", "ts", "tsx", "css", "scss", "html", "htm",
            "py", "rb", "go", "rs", "java", "kt", "kts",
            "sh", "bash", "zsh", "fish", "env"
        ]
        return editableExtensions.contains(pathExtension.lowercased())
    }

    var isGeneratedTextPreviewFile: Bool {
        let previewExtensions: Set<String> = [
            "log", "aux", "bbl", "blg", "toc", "out", "fls", "fdb_latexmk"
        ]
        return previewExtensions.contains(pathExtension.lowercased())
    }

    var presentation: FilePresentation {
        switch pathExtension.lowercased() {
        case "pdf":
            return .pdf(self)
        case "png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "eps":
            return .image(self)
        default:
            return .external(self)
        }
    }
}

private enum SettingsStore {
    private static let key = "TEXnologia.AppSettings"
    private static let legacyKey = "PaperForge.AppSettings"
    private static let spellMigrationKey = "TEXnologia.AppSettings.SpellCheckingMigrated"

    static func loadMigratingIfNeeded() -> AppSettings {
        var settings = load()

        if !UserDefaults.standard.bool(forKey: spellMigrationKey) {
            settings.editorSpellChecking = true
            settings.editorWrapLines = true
            save(settings)
            UserDefaults.standard.set(true, forKey: spellMigrationKey)
        }

        return settings
    }

    private static func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: key) ?? UserDefaults.standard.data(forKey: legacyKey),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }

        return settings
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private enum TextFileLoader {
    enum LoadError: LocalizedError {
        case fileTooLarge(byteCount: Int)
        case unsupportedTextEncoding

        var errorDescription: String? {
            switch self {
            case .fileTooLarge(let byteCount):
                return "The file is too large to edit safely (\(Self.formatBytes(byteCount)))."
            case .unsupportedTextEncoding:
                return "Unsupported text encoding."
            }
        }

        private static func formatBytes(_ byteCount: Int) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        }
    }

    private static let maxEditableBytes = 2_000_000
    private static let maxPreviewBytes = 600_000

    static func loadEditable(url: URL) throws -> (text: String, encoding: String.Encoding) {
        let byteCount = fileSize(url: url)
        if byteCount > maxEditableBytes {
            throw LoadError.fileTooLarge(byteCount: byteCount)
        }

        let data = try Data(contentsOf: url)
        if data.isEmpty {
            return ("", .utf8)
        }

        return try decode(data)
    }

    static func loadPreview(url: URL) throws -> TextFilePreview {
        let byteCount = fileSize(url: url)
        let previewedByteCount = min(byteCount, maxPreviewBytes)
        let data = try readPrefix(url: url, byteCount: previewedByteCount)
        let decoded = try decode(data)
        let text = decoded.text + (previewedByteCount < byteCount ? "\n\n--- Preview truncated at \(formatBytes(previewedByteCount)) of \(formatBytes(byteCount)). Open externally to inspect the full file. ---\n" : "")

        return TextFilePreview(
            fileURL: url,
            text: text,
            byteCount: byteCount,
            previewedByteCount: previewedByteCount,
            encodingDescription: encodingDescription(decoded.encoding)
        )
    }

    private static func decode(_ data: Data) throws -> (text: String, encoding: String.Encoding) {
        guard !looksBinary(data) else {
            throw LoadError.unsupportedTextEncoding
        }

        for encoding in candidateEncodings {
            if let text = String(data: data, encoding: encoding) {
                return (text, encoding)
            }
        }

        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }

        throw LoadError.unsupportedTextEncoding
    }

    private static func readPrefix(url: URL, byteCount: Int) throws -> Data {
        guard byteCount > 0 else { return Data() }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        if #available(macOS 10.15.4, *) {
            return try handle.read(upToCount: byteCount) ?? Data()
        }

        return handle.readData(ofLength: byteCount)
    }

    private static func fileSize(url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private static func looksBinary(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        return data.prefix(min(data.count, 4096)).contains(0)
    }

    private static func formatBytes(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private static func encodingDescription(_ encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case .utf16: return "UTF-16"
        case .utf16LittleEndian: return "UTF-16 LE"
        case .utf16BigEndian: return "UTF-16 BE"
        case .isoLatin1: return "ISO Latin 1"
        case .windowsCP1252: return "Windows CP1252"
        case .macOSRoman: return "Mac OS Roman"
        default: return "Text"
        }
    }

    static func prettyPrintedJSONIfPossible(_ text: String) -> String {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            JSONSerialization.isValidJSONObject(object),
            let prettyData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            ),
            let pretty = String(data: prettyData, encoding: .utf8)
        else {
            return text
        }

        return pretty + "\n"
    }

    private static var candidateEncodings: [String.Encoding] {
        var encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian
        ]

        let ianaNames = ["EUC-KR", "windows-949", "CP949"]
        for name in ianaNames {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            if nsEncoding != UInt(kCFStringEncodingInvalidId) {
                encodings.append(String.Encoding(rawValue: nsEncoding))
            }
        }

        encodings.append(contentsOf: [
            .isoLatin1,
            .windowsCP1252,
            .macOSRoman
        ])

        return encodings
    }
}
