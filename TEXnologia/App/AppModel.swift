import AppKit
import CoreFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var workspace: Workspace?
    @Published var selectedFileURL: URL?
    @Published var editorText: String = ""
    @Published var selectedFilePresentation: FilePresentation = .none
    @Published var projectIndex: ProjectIndex = .empty
    @Published var buildIssues: [BuildIssue] = []
    @Published var pdfDocumentURL: URL?
    @Published var editorJump: EditorJump?
    @Published var settings: AppSettings = .default
    @Published var statusMessage: String = "Drop a LaTeX folder, .tex file, or .zip archive to begin."
    @Published var isImporting: Bool = false

    private let indexer = ProjectIndexer()
    private let buildService = LatexBuildService()
    private var selectedFileEncoding: String.Encoding = .utf8

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

        workspace = Workspace(
            id: WorkspaceID(),
            rootURL: rootURL,
            mainFileURL: detectedRoot,
            displayName: displayName
        )
        selectedFileURL = detectedRoot
        selectedFilePresentation = detectedRoot == nil ? .none : .text
        projectIndex = indexer.indexProject(rootURL: rootURL, mainFileURL: detectedRoot)
        loadSelectedFile()
        statusMessage = detectedRoot == nil
            ? "Opened \(displayName), but no root .tex file was detected yet."
            : "Opened \(displayName)."
    }

    func loadSelectedFile() {
        guard let selectedFileURL else {
            editorText = ""
            selectedFilePresentation = .none
            return
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: selectedFileURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return
        }

        guard selectedFileURL.isEditableTextFile else {
            editorText = ""
            selectedFilePresentation = selectedFileURL.presentation
            if case .pdf(let url) = selectedFilePresentation {
                pdfDocumentURL = url
                statusMessage = "Opened \(url.lastPathComponent) in the PDF viewer."
            } else {
                statusMessage = "Selected \(selectedFileURL.lastPathComponent)."
            }
            return
        }

        do {
            let loaded = try TextFileLoader.load(url: selectedFileURL)
            editorText = selectedFileURL.pathExtension.lowercased() == "json"
                ? TextFileLoader.prettyPrintedJSONIfPossible(loaded.text)
                : loaded.text
            selectedFileEncoding = loaded.encoding
            selectedFilePresentation = .text
            statusMessage = "Opened \(selectedFileURL.lastPathComponent)."
        } catch {
            editorText = ""
            selectedFilePresentation = .external(selectedFileURL)
            statusMessage = "Could not read \(selectedFileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func selectFile(_ url: URL) {
        selectedFileURL = url
        loadSelectedFile()
    }

    func jumpToIssue(_ issue: BuildIssue) {
        guard let location = issue.location else {
            statusMessage = issue.message
            return
        }

        selectedFileURL = location.fileURL
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

        if let preferredSelection, fileManager.fileExists(atPath: preferredSelection.path) {
            selectedFileURL = preferredSelection
        } else if let selectedFileURL, fileManager.fileExists(atPath: selectedFileURL.path) {
            self.selectedFileURL = selectedFileURL
        } else {
            selectedFileURL = mainFile
        }

        loadSelectedFile()
    }

    func setStatus(_ message: String) {
        statusMessage = message
    }

    func saveSelectedFile() {
        guard let selectedFileURL else { return }
        guard selectedFilePresentation == .text else { return }
        do {
            try editorText.write(to: selectedFileURL, atomically: true, encoding: selectedFileEncoding)
            statusMessage = "Saved \(selectedFileURL.lastPathComponent)."
        } catch {
            statusMessage = "Could not save \(selectedFileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func saveSelectedFileAndBuildIfNeeded() {
        saveSelectedFile()
        if settings.autoBuildOnSave {
            build()
        }
    }

    func build() {
        guard let workspace, let mainFileURL = workspace.mainFileURL else { return }
        saveSelectedFile()
        statusMessage = "Building \(mainFileURL.lastPathComponent)..."

        Task {
            let configuration = BuildConfiguration.default(
                rootFile: mainFileURL,
                engine: settings.defaultEngine,
                shellEscape: settings.shellEscapeEnabled
            )
            let result = await buildService.build(configuration: configuration)
            buildIssues = result.issues
            pdfDocumentURL = result.pdfURL
            statusMessage = result.succeeded
                ? "Build succeeded."
                : "Build failed with \(result.issues.count) issue(s)."
        }
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
    var isEditableTextFile: Bool {
        let editableExtensions: Set<String> = [
            "tex", "bib", "sty", "cls", "ltx",
            "txt", "md", "markdown",
            "json", "jsonc", "yaml", "yml", "toml", "xml", "plist",
            "swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx",
            "js", "jsx", "ts", "tsx", "css", "scss", "html", "htm",
            "py", "rb", "go", "rs", "java", "kt", "kts",
            "sh", "bash", "zsh", "fish", "env",
            "log", "aux", "bbl", "blg", "toc", "out", "fls"
        ]
        return editableExtensions.contains(pathExtension.lowercased())
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
    static func load(url: URL) throws -> (text: String, encoding: String.Encoding) {
        let data = try Data(contentsOf: url)
        if data.isEmpty {
            return ("", .utf8)
        }

        for encoding in candidateEncodings {
            if let text = String(data: data, encoding: encoding) {
                return (text, encoding)
            }
        }

        throw NSError(
            domain: "TEXnologia.TextFileLoader",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported text encoding."]
        )
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
