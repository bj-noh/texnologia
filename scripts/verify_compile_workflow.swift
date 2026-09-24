import AppKit
import Foundation
import PDFKit
import SwiftUI

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private final class ControlledBuilder {
    private(set) var configurations: [BuildConfiguration] = []
    private(set) var sourceContents: [String] = []
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0
    private var continuations: [CheckedContinuation<BuildResult, Never>] = []

    func build(_ configuration: BuildConfiguration) async -> BuildResult {
        configurations.append(configuration)
        sourceContents.append((try? String(contentsOf: configuration.rootFile, encoding: .utf8)) ?? "<unreadable>")
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        defer { activeCount -= 1 }
        return await withCheckedContinuation { continuations.append($0) }
    }

    func completeNext(with result: BuildResult) throws {
        guard !continuations.isEmpty else {
            throw VerificationFailure(description: "No pending build to complete")
        }
        continuations.removeFirst().resume(returning: result)
    }
}

private struct ProjectFixture {
    let root: URL
    let source: URL
    let initialText: String

    var pdf: URL { root.appendingPathComponent("result.pdf") }
}

@main
private struct VerifyCompileWorkflow {
    @MainActor
    static func main() async {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("texnologia-workflow-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporaryRoot) }

            try await saveAndCompileIgnoresAutomaticPreference(in: temporaryRoot)
            print("PASS explicit save compiles once after writing, even with automatic builds disabled")
            try await failedBuildClearsBusyState(in: temporaryRoot)
            print("PASS failed build clears progress and reports the build issue")
            try await failedSaveDoesNotBuild(in: temporaryRoot)
            print("PASS failed save preserves the error and never starts a build")
            try await repeatedSavesCoalesce(in: temporaryRoot)
            print("PASS saves during a build reach disk immediately and coalesce into one serial follow-up")
            try await configurationIsCapturedAtRequestTime(in: temporaryRoot)
            print("PASS each build uses the settings captured when it was requested")
            try await sessionSwitchKeepsItsOwnResults(in: temporaryRoot)
            print("PASS finishing a previous session does not replace the active session's result")
            try await previewFocusDoesNotRedirectResult(in: temporaryRoot)
            print("PASS changing preview focus does not redirect a running build's result")
            try await mainFileChangeRejectsStaleResult(in: temporaryRoot)
            print("PASS changing the project's main file rejects the previous build's result")
            try await readOnlySelectionCanStillCompile(in: temporaryRoot)
            print("PASS a read-only selection still permits compiling the main document")
            try await saveDuringFileLoadPreservesDisk(in: temporaryRoot)
            print("PASS saving before a file finishes loading cannot replace its contents")
            try await rebuiltPDFReloadsAtTheSameURL(in: temporaryRoot)
            print("PASS a rebuilt PDF reloads new pages at the same file URL")
            try await openTeXDocumentSelectsItsOwnMain(in: temporaryRoot)
            print("PASS opening a TeX document selects it as the new project's main file")
            try await openBibliographySelectsTextAndDetectsMain(in: temporaryRoot)
            print("PASS opening a bibliography selects its text and detects the companion main document")
            try await standaloneBibliographyCanBeEditedAndSaved(in: temporaryRoot)
            print("PASS a standalone bibliography can be edited and saved without inventing a compile root")
            try await reopeningNestedDocumentsPreservesTheProjectAndDirtyBuffers(in: temporaryRoot)
            print("PASS nested TeX and bibliography opens reuse their project, main file, and unsaved buffers")
            try await statusMessagesExpireAfterTheLatestUpdate()
            print("PASS status messages expire and repeated messages restart the timer")
            try await sourceNavigationWaitsForFileLoad(in: temporaryRoot)
            print("PASS source navigation waits for the destination file to load")
            try await pdfNavigationWaitsForDocumentLoad(in: temporaryRoot)
            print("PASS PDF navigation survives asynchronous loading without repeating or moving another PDF")
            try sourceNavigationDoesNotReplayInAnotherEditor()
            print("PASS source navigation affects only the active editor and does not replay after focus changes")
            try pdfClicksTrackTheCorrectPane(in: temporaryRoot)
            print("PASS reverse navigation uses clicked PDF coordinates in the requested pane")
            if CommandLine.arguments.contains("--real-tex") {
                try await installedTeXProducesPDF(in: temporaryRoot)
                print("PASS the installed TeX engine compiles a saved article into a PDF")
                print("PASS compile workflow: 20 controlled scenarios + installed TeX")
            } else {
                print("PASS compile workflow: 20 controlled scenarios")
            }
        } catch {
            fputs("FAIL compile workflow: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    @MainActor
    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw VerificationFailure(description: message) }
    }

    @MainActor
    private static func eventually(_ message: String, timeout: TimeInterval = 4, _ predicate: () -> Bool) async throws {
        for _ in 0..<Int(timeout * 100) {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw VerificationFailure(description: "Timed out: \(message)")
    }

    private static func makeProject(in directory: URL, name: String) throws -> ProjectFixture {
        let root = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("main.tex")
        let initialText = "\\documentclass{article}\n\\begin{document}\n\(name) original.\n\\end{document}\n"
        try initialText.write(to: source, atomically: true, encoding: .utf8)
        return ProjectFixture(root: root, source: source, initialText: initialText)
    }

    @MainActor
    private static func open(_ project: ProjectFixture, in model: AppModel) async throws {
        model.openProject(at: project.root, preferredMainFile: project.source)
        try await eventually("project text to load") {
            model.editorFileURL == project.source && model.editorText == project.initialText
                && model.canSaveEditorFile && model.isEditorSaved
        }
    }

    @MainActor
    private static func model(using builder: ControlledBuilder) -> AppModel {
        AppModel(loadPersistedState: false, buildDocument: { configuration in
            await builder.build(configuration)
        })
    }

    private static func succeeded(pdf: URL) -> BuildResult {
        BuildResult(succeeded: true, pdfURL: pdf, issues: [], rawLog: "Finished")
    }

    private static func issue(_ message: String) -> BuildIssue {
        BuildIssue(severity: .error, message: message, location: nil, rawLogExcerpt: message)
    }

    @MainActor
    private static func saveAndCompileIgnoresAutomaticPreference(in root: URL) async throws {
        let project = try makeProject(in: root, name: "explicit-save")
        let builder = ControlledBuilder()
        let model = model(using: builder)
        try await open(project, in: model)
        model.settings.autoBuildOnSave = false
        let edited = project.initialText.replacingOccurrences(of: "original", with: "saved revision")
        model.updateEditorText(edited)

        model.saveAndCompile()

        try require(model.isCompiling, "Progress must become active before the build task starts")
        try require(model.compilingFileName == "main.tex", "Progress must identify the document being built")
        let diskText = try String(contentsOf: project.source, encoding: .utf8)
        try require(diskText == edited, "Explicit save must write the latest editor contents immediately")
        try require(model.isEditorSaved, "The saved editor must become clean")
        try require(model.history.count == 1, "One explicit save must not create duplicate history snapshots")
        try await eventually("first build to start") { builder.configurations.count == 1 }
        try require(builder.sourceContents == [edited], "The build must read the newly saved text")
        try builder.completeNext(with: succeeded(pdf: project.pdf))
        try await eventually("successful build to stop showing progress") { !model.isCompiling }
        try require(model.compilingFileName == nil, "A finished build must clear its progress label")
        try require(model.primaryPreviewPresentation == .pdf(project.pdf), "A successful build must update its preview")
        try require(model.statusMessage == "Compile succeeded.", "Success must be reported")
        try require(builder.configurations.count == 1, "One explicit save must only launch one build")
    }

    @MainActor
    private static func failedBuildClearsBusyState(in root: URL) async throws {
        let project = try makeProject(in: root, name: "failed-build")
        let builder = ControlledBuilder()
        let model = model(using: builder)
        try await open(project, in: model)
        model.saveAndCompile()
        try require(model.isCompiling, "A failing build must initially show progress")
        try await eventually("failing build to start") { builder.configurations.count == 1 }
        let buildIssue = issue("The TeX engine is unavailable")
        try builder.completeNext(with: BuildResult(succeeded: false, pdfURL: nil, issues: [buildIssue], rawLog: buildIssue.message))
        try await eventually("failed build to stop showing progress") { !model.isCompiling }
        try require(model.compilingFileName == nil, "Failure must clear the progress label")
        try require(model.buildIssues == [buildIssue], "The failed build must expose its diagnostic")
        try require(model.statusMessage.contains("Compile failed"), "Failure must be reported")
    }

    @MainActor
    private static func failedSaveDoesNotBuild(in root: URL) async throws {
        let project = try makeProject(in: root, name: "failed-save")
        let builder = ControlledBuilder()
        let model = model(using: builder)
        try await open(project, in: model)
        model.updateEditorText(project.initialText + "% unsaved edit\n")
        // A directory at the file destination fails reliably, including privileged test runs.
        try FileManager.default.removeItem(at: project.source)
        try FileManager.default.createDirectory(at: project.source, withIntermediateDirectories: false)

        model.saveAndCompile()

        try require(!model.isCompiling, "A failed write must not start build progress")
        try require(!model.isEditorSaved, "A failed write must leave the editor dirty")
        let errorMessage = model.statusMessage
        try require(errorMessage.hasPrefix("Could not save main.tex:"), "The save error must remain visible")
        await Task.yield()
        await Task.yield()
        try require(builder.configurations.isEmpty, "A failed write must never invoke the builder")
        try require(model.statusMessage == errorMessage, "A build status must not replace the save failure")
    }

    @MainActor
    private static func repeatedSavesCoalesce(in root: URL) async throws {
        let project = try makeProject(in: root, name: "coalesced-saves")
        let builder = ControlledBuilder()
        let model = model(using: builder)
        try await open(project, in: model)
        model.updateEditorText(project.initialText + "% first revision\n")
        model.saveAndCompile()
        try await eventually("initial slow build to start") { builder.configurations.count == 1 }

        let second = project.initialText + "% second revision\n"
        model.updateEditorText(second)
        model.saveAndCompile()
        let savedSecond = try String(contentsOf: project.source, encoding: .utf8)
        try require(savedSecond == second, "Saving during a build must reach disk immediately")
        let latest = project.initialText + "% latest revision\n"
        model.updateEditorText(latest)
        model.saveAndCompile()
        model.compile()
        let savedLatest = try String(contentsOf: project.source, encoding: .utf8)
        try require(savedLatest == latest, "The newest save must replace the previous queued version on disk")
        await Task.yield()
        try require(builder.configurations.count == 1, "Repeated commands must not launch simultaneous builds")
        try require(builder.activeCount == 1, "Exactly one builder must remain active")

        try builder.completeNext(with: succeeded(pdf: project.pdf))
        try await eventually("one coalesced follow-up build to start") { builder.configurations.count == 2 }
        try require(model.isCompiling, "Progress must stay active while the queued build runs")
        try require(builder.sourceContents[1] == latest, "The follow-up build must read the latest saved revision")
        try require(builder.maximumActiveCount == 1, "Queued builds must never overlap")
        try builder.completeNext(with: succeeded(pdf: project.pdf))
        try await eventually("all queued builds to finish") { !model.isCompiling }
        try require(builder.configurations.count == 2, "Multiple queued requests for one project must coalesce into one follow-up")
        try require(builder.activeCount == 0, "Finishing the queue must leave no build running")
    }

    @MainActor
    private static func configurationIsCapturedAtRequestTime(in root: URL) async throws {
        let project = try makeProject(in: root, name: "configuration-snapshot")
        let builder = ControlledBuilder()
        let model = model(using: builder)
        try await open(project, in: model)
        model.settings.defaultEngine = .xeLaTeX
        model.settings.toolchainYear = .texLive2025
        model.settings.shellEscapeEnabled = true
        model.saveAndCompile()
        model.settings.defaultEngine = .pdfLaTeX
        model.settings.toolchainYear = .texLive2024
        model.settings.shellEscapeEnabled = false

        try await eventually("build using captured settings to start") { builder.configurations.count == 1 }
        let captured = builder.configurations[0]
        try require(captured.engine == .xeLaTeX && captured.toolchainYear == .texLive2025 && captured.shellEscape,
                    "Settings changed after the command must not affect the requested build")
        try require(captured.rootFile == project.source, "The captured build must use the requested root document")
        try builder.completeNext(with: succeeded(pdf: project.pdf))
        try await eventually("snapshot build to complete") { !model.isCompiling }
    }

    @MainActor
    private static func sessionSwitchKeepsItsOwnResults(in root: URL) async throws {
        let first = try makeProject(in: root, name: "session-A")
        let second = try makeProject(in: root, name: "session-B")
        let builder = ControlledBuilder()
        let model = model(using: builder)
        try await open(first, in: model)
        let firstID = model.workspace!.id
        try await open(second, in: model)
        let secondID = model.workspace!.id
        model.activateSession(firstID)
        try await eventually("first session text to load") { model.editorFileURL == first.source && model.editorText == first.initialText && model.isEditorSaved }
        model.saveAndCompile()
        try await eventually("first session build to start") { builder.configurations.count == 1 }
        model.activateSession(secondID)
        try await eventually("second session text to load") { model.editorFileURL == second.source && model.editorText == second.initialText && model.isEditorSaved }
        let existingIssue = issue("Second session diagnostic")
        model.buildIssues = [existingIssue]
        model.pdfDocumentURL = second.pdf
        model.primaryPreviewPresentation = .pdf(second.pdf)
        model.statusMessage = "Second session remains active"

        try builder.completeNext(with: succeeded(pdf: first.pdf))
        try await eventually("previous session build to complete") { !model.isCompiling }
        try require(model.workspace?.id == secondID, "Build completion must not activate another session")
        try require(model.pdfDocumentURL == second.pdf && model.primaryPreviewPresentation == .pdf(second.pdf),
                    "The previous session must not replace the active session's PDF")
        try require(model.buildIssues == [existingIssue], "The previous session must not replace current diagnostics")
        try require(model.statusMessage == "Second session remains active", "Stale build status must not replace active session status")
    }

    @MainActor
    private static func previewFocusDoesNotRedirectResult(in root: URL) async throws {
        let project = try makeProject(in: root, name: "preview-focus")
        let builder = ControlledBuilder()
        let model = model(using: builder)
        try await open(project, in: model)
        let secondaryPDF = project.root.appendingPathComponent("reference.pdf")
        model.secondaryPreviewPresentation = .pdf(secondaryPDF)
        model.focusedPreviewPane = .primary
        model.saveAndCompile()
        try await eventually("preview build to start") { builder.configurations.count == 1 }
        model.focusedPreviewPane = .secondary
        try builder.completeNext(with: succeeded(pdf: project.pdf))
        try await eventually("preview build to finish") { !model.isCompiling }
        try require(model.primaryPreviewPresentation == .pdf(project.pdf), "Build output belongs to the preview selected at request time")
        try require(model.secondaryPreviewPresentation == .pdf(secondaryPDF), "A newly focused reference preview must not be replaced")
        try require(model.focusedPreviewPane == .secondary, "Build completion must not steal preview focus")
    }

    @MainActor
    private static func mainFileChangeRejectsStaleResult(in root: URL) async throws {
        let project = try makeProject(in: root, name: "changed-main")
        let builder = ControlledBuilder()
        let model = model(using: builder)
        try await open(project, in: model)
        model.saveAndCompile()
        try await eventually("old main file build to start") { builder.configurations.count == 1 }
        let newMain = project.root.appendingPathComponent("new-main.tex")
        try project.initialText.write(to: newMain, atomically: true, encoding: .utf8)
        model.setMainFile(newMain)
        model.statusMessage = "New main file selected"
        try builder.completeNext(with: succeeded(pdf: project.pdf))
        try await eventually("old main file build to complete") { !model.isCompiling }
        try require(model.workspace?.mainFileURL == newMain, "Build completion must preserve the new main file")
        try require(model.pdfDocumentURL == nil && model.primaryPreviewPresentation == .none, "The old main file's PDF must not replace the new main file's preview")
        try require(model.statusMessage == "New main file selected", "The old main file's status must not replace the current selection status")
    }

    @MainActor
    private static func readOnlySelectionCanStillCompile(in root: URL) async throws {
        let project = try makeProject(in: root, name: "read-only-selection")
        let builder = ControlledBuilder()
        let model = model(using: builder)
        try await open(project, in: model)
        let logURL = project.root.appendingPathComponent("main.log")
        try "Existing compiler log".write(to: logURL, atomically: true, encoding: .utf8)
        model.selectFile(logURL)
        try await eventually("read-only log preview to load") {
            if case .readOnlyText = model.selectedFilePresentation { return true }
            return false
        }
        try require(!model.canSaveEditorFile, "A generated log must remain read-only")
        model.compile()
        try require(model.isCompiling, "A read-only selection must not block compiling the project")
        try await eventually("build from read-only selection to start") { builder.configurations.count == 1 }
        try require(builder.configurations[0].rootFile == project.source, "Compile must use the main TeX document, not the selected log")
        try builder.completeNext(with: succeeded(pdf: project.pdf))
        try await eventually("build from read-only selection to finish") { !model.isCompiling }
    }

    @MainActor
    private static func saveDuringFileLoadPreservesDisk(in root: URL) async throws {
        let project = try makeProject(in: root, name: "loading-save")
        let builder = ControlledBuilder()
        let model = model(using: builder)
        model.openProject(at: project.root, preferredMainFile: project.source)
        try require(model.isLoadingEditorFile, "Opening a file must expose its loading state synchronously")
        model.saveAndCompile()
        let diskText = try String(contentsOf: project.source, encoding: .utf8)
        try require(diskText == project.initialText, "Save during loading must not replace unread contents with an empty buffer")
        try require(!model.isCompiling, "The app must not compile an unread editor buffer")
        try await eventually("protected file load to complete") { !model.isLoadingEditorFile && model.isEditorSaved }
        try require(builder.configurations.isEmpty, "Save during loading must not enqueue a build")
        try require(model.editorText == project.initialText, "The original document must still load into the editor")
    }

    @MainActor
    private static func installedTeXProducesPDF(in root: URL) async throws {
        let project = try makeProject(in: root, name: "installed-tex")
        let model = AppModel(loadPersistedState: false)
        try await open(project, in: model)
        model.settings.autoBuildOnSave = false
        let edited = project.initialText.replacingOccurrences(of: "original", with: "saved and compiled")
        model.updateEditorText(edited)
        model.saveAndCompile()
        try require(model.isCompiling, "The real TeX build must expose progress immediately")
        try await eventually("installed TeX engine to finish", timeout: 45) { !model.isCompiling }
        try require(model.statusMessage == "Compile succeeded.",
                    "Installed TeX failed: \(model.buildIssues.map(\.message).joined(separator: "; "))")
        guard let pdfURL = model.pdfDocumentURL else {
            throw VerificationFailure(description: "Installed TeX returned no PDF URL")
        }
        let pdf = try Data(contentsOf: pdfURL)
        try require(pdf.starts(with: Data("%PDF-".utf8)), "Installed TeX must write an actual PDF file")
        let savedText = try String(contentsOf: project.source, encoding: .utf8)
        try require(savedText == edited, "The real build must preserve the saved source contents")
    }

    @MainActor
    private static func rebuiltPDFReloadsAtTheSameURL(in root: URL) async throws {
        _ = NSApplication.shared
        let pdfURL = root.appendingPathComponent("rebuilt-preview.pdf")
        let pdfView = PDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        let coordinator = PDFKitRepresentable.Coordinator()
        try writePDF(pageCount: 1, to: pdfURL)
        coordinator.load(pdfURL, refreshID: 0, into: pdfView)
        try await eventually("original one-page PDF to load") { pdfView.document?.pageCount == 1 }

        try writePDF(pageCount: 2, to: pdfURL)
        coordinator.load(pdfURL, refreshID: 1, into: pdfView)
        try await eventually("rebuilt PDF at the same URL to expose both pages") { pdfView.document?.pageCount == 2 }
    }

    @MainActor
    private static func statusMessagesExpireAfterTheLatestUpdate() async throws {
        let model = AppModel(loadPersistedState: false, statusMessageDuration: .milliseconds(300))
        model.setStatus("Saved main.tex.")
        try await Task.sleep(for: .milliseconds(200))
        model.setStatus("Saved main.tex.")
        try await Task.sleep(for: .milliseconds(200))
        try require(model.statusMessage == "Saved main.tex.", "The earlier timer must not clear a repeated message")
        try await eventually("latest status message to expire") { model.statusMessage.isEmpty }
    }

    @MainActor
    private static func sourceNavigationWaitsForFileLoad(in root: URL) async throws {
        let project = try makeProject(in: root, name: "source navigation")
        let chapter = project.root.appendingPathComponent("chapter.tex")
        let chapterText = (1...100).map { "Line \($0)" }.joined(separator: "\n")
        try chapterText.write(to: chapter, atomically: true, encoding: .utf8)
        let model = AppModel(loadPersistedState: false)
        model.openProjectResource(at: project.source)
        try await eventually("main source to load") { model.canSaveEditorFile }
        model.revealSourceLocation(TextLocation(fileURL: chapter, line: 42, column: 3))
        try require(model.editorJump == nil, "Do not consume the jump against the old or empty buffer")
        try await eventually("chapter text and jump to become available together") {
            model.editorText == chapterText && model.editorJump?.location.fileURL == chapter
                && model.editorJump?.location.line == 42 && !model.isLoadingEditorFile
        }
    }

    @MainActor
    private static func pdfNavigationWaitsForDocumentLoad(in root: URL) async throws {
        let url = root.appendingPathComponent("navigation.pdf")
        try writePDF(pageCount: 2, to: url)
        let view = PDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        let coordinator = PDFKitRepresentable.Coordinator()
        let target = PDFNavigationTarget(pdfURL: url, paneID: .primary, page: 2, x: 50, y: 100)
        coordinator.load(url, into: view)
        coordinator.navigate(to: target, in: view)
        try await eventually("PDF load followed by navigation to page two") {
            guard let document = view.document, let page = view.currentPage else { return false }
            return document.index(for: page) == 1
        }
        guard let first = view.document?.page(at: 0) else { throw VerificationFailure(description: "Missing first PDF page") }
        view.go(to: first)
        coordinator.navigate(to: target, in: view)
        try require(view.currentPage === first, "A consumed request must not jump again on every view update")
        let unrelated = PDFNavigationTarget(pdfURL: root.appendingPathComponent("other.pdf"), paneID: .primary, page: 2, x: 50, y: 100)
        coordinator.navigate(to: unrelated, in: view)
        try require(view.currentPage === first, "A request for another PDF must not navigate this document")
    }

    @MainActor
    private static func sourceNavigationDoesNotReplayInAnotherEditor() throws {
        let first = NSTextView()
        let second = NSTextView()
        first.string = "First\nSecond\nThird"
        second.string = first.string
        first.setSelectedRange(NSRange(location: 0, length: 0))
        second.setSelectedRange(NSRange(location: 0, length: 0))
        let primary = LaTeXEditorView.Coordinator(text: .constant(first.string), settings: .default, syntaxMode: .latex)
        let secondary = LaTeXEditorView.Coordinator(text: .constant(second.string), settings: .default, syntaxMode: .latex)
        let jump = EditorJump(location: TextLocation(fileURL: URL(fileURLWithPath: "/tmp/main.tex"), line: 3, column: 0))
        SyncTeXBridge.shared.editorTextView = first
        primary.performJumpIfNeeded(jump, in: first)
        secondary.performJumpIfNeeded(jump, in: second)
        try require(first.selectedRange().location == 13 && second.selectedRange().location == 0,
                    "Only the active source pane should move: primary=\(first.selectedRange()), secondary=\(second.selectedRange())")
        SyncTeXBridge.shared.editorTextView = second
        secondary.performJumpIfNeeded(jump, in: second)
        try require(second.selectedRange().location == 0, "Focusing another editor must not replay the old jump")
        SyncTeXBridge.shared.editorTextView = nil
    }

    @MainActor
    private static func pdfClicksTrackTheCorrectPane(in root: URL) throws {
        let firstURL = root.appendingPathComponent("click-primary.pdf")
        let secondURL = root.appendingPathComponent("click-secondary.pdf")
        try writePDF(pageCount: 1, to: firstURL)
        try writePDF(pageCount: 1, to: secondURL)
        let views = [PDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 600)),
                     PDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))]
        for (index, pane) in [PreviewPaneID.primary, .secondary].enumerated() {
            let view = views[index]
            view.document = PDFDocument(url: index == 0 ? firstURL : secondURL)
            view.layoutDocumentView()
            guard let page = view.document?.page(at: 0) else { throw VerificationFailure(description: "Missing PDF page") }
            let point = view.convert(NSPoint(x: 80, y: 450), from: page)
            SyncTeXBridge.shared.recordPDFClick(at: point, in: view, paneID: pane)
        }
        for (index, pane) in [PreviewPaneID.primary, .secondary].enumerated() {
            guard let location = SyncTeXBridge.shared.currentPDFLocation(in: pane) else {
                throw VerificationFailure(description: "PDF click was not recorded")
            }
            try require(location.pdfURL == (index == 0 ? firstURL : secondURL), "Use the requested pane, not the last rendered one")
            try require(location.page == 1 && abs(location.x - 80) < 0.01 && abs(location.y - 150) < 0.01,
                        "Convert the clicked point from PDFKit to SyncTeX coordinates")
        }
        withExtendedLifetime(views) {}
    }

    private static func writePDF(pageCount: Int, to url: URL) throws {
        var page = CGRect(x: 0, y: 0, width: 400, height: 600)
        guard let context = CGContext(url as CFURL, mediaBox: &page, nil) else {
            throw VerificationFailure(description: "Could not create the temporary PDF")
        }
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(page)
            context.endPDFPage()
        }
        context.closePDF()
    }

    @MainActor
    private static func openTeXDocumentSelectsItsOwnMain(in root: URL) async throws {
        let project = try makeProject(in: root, name: "open tex document")
        let requestedURL = project.root.appendingPathComponent("requested article.tex")
        let requestedText = project.initialText.replacingOccurrences(of: "original", with: "requested article")
        try requestedText.write(to: requestedURL, atomically: true, encoding: .utf8)
        let model = AppModel(loadPersistedState: false)

        model.openProjectResource(at: requestedURL)

        try await eventually("the explicitly opened TeX document to load") {
            model.selectedFileURL == requestedURL && model.editorFileURL == requestedURL
                && model.editorText == requestedText && model.canSaveEditorFile
        }
        try require(model.workspace?.rootURL == project.root, "A freshly opened TeX document must use its containing folder")
        try require(model.workspace?.mainFileURL == requestedURL,
                    "An explicitly opened TeX document must remain the main file even when main.tex also exists")
        try require(model.sessions.count == 1, "One TeX open must create only one project session")
        try require(model.currentOpenEditorTabs.contains(requestedURL), "The opened TeX document must have an editor tab")
        try require(model.isEditorSaved, "Opening a TeX document must not mark its original text as modified")
    }

    @MainActor
    private static func openBibliographySelectsTextAndDetectsMain(in root: URL) async throws {
        let project = try makeProject(in: root, name: "open bibliography")
        let bibliographyURL = project.root.appendingPathComponent("paper references.bib")
        let bibliographyText = "@article{reference,\n  title = {Companion bibliography}\n}\n"
        try bibliographyText.write(to: bibliographyURL, atomically: true, encoding: .utf8)
        let model = AppModel(loadPersistedState: false)

        model.openProjectResource(at: bibliographyURL)

        try await eventually("the bibliography rather than its companion main file to load") {
            model.selectedFileURL == bibliographyURL && model.editorFileURL == bibliographyURL
                && model.editorText == bibliographyText && model.canSaveEditorFile
        }
        try require(model.workspace?.rootURL == project.root, "The bibliography's parent folder must become its project")
        try require(model.workspace?.mainFileURL?.resolvingSymlinksInPath() == project.source.resolvingSymlinksInPath(),
                    "The companion main.tex must remain the compile root (actual: \(model.workspace?.mainFileURL?.absoluteString ?? "nil"); expected: \(project.source.absoluteString))")
        try require(model.sessions.count == 1, "Opening a bibliography must create only one project session")
        try require(model.currentOpenEditorTabs.contains(bibliographyURL), "The bibliography must have its own editor tab")
        try require(model.isEditorSaved, "A newly opened bibliography must retain its saved state")
    }

    @MainActor
    private static func standaloneBibliographyCanBeEditedAndSaved(in root: URL) async throws {
        let directory = root.appendingPathComponent("standalone bibliography", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bibliographyURL = directory.appendingPathComponent("references.bib")
        let originalText = "@book{reference,\n  title = {Original title}\n}\n"
        try originalText.write(to: bibliographyURL, atomically: true, encoding: .utf8)
        let builder = ControlledBuilder()
        let model = model(using: builder)

        model.openProjectResource(at: bibliographyURL)

        try await eventually("the standalone bibliography to become editable") {
            model.editorFileURL == bibliographyURL && model.editorText == originalText && model.canSaveEditorFile
        }
        try require(model.selectedFileURL == bibliographyURL, "The standalone bibliography must remain selected")
        try require(model.workspace?.rootURL == directory && model.sessions.count == 1,
                    "A bibliography without TeX files still needs a usable project session")
        try require(model.workspace?.mainFileURL == nil, "A bibliography cannot be used as a LaTeX compile root")
        let editedText = originalText.replacingOccurrences(of: "Original title", with: "Edited title")
        model.updateEditorText(editedText)
        model.saveAndCompile()
        let diskText = try String(contentsOf: bibliographyURL, encoding: .utf8)
        try require(diskText == editedText && model.isEditorSaved, "The save command must write standalone bibliography edits")
        await Task.yield()
        try require(!model.isCompiling && builder.configurations.isEmpty,
                    "Saving a standalone bibliography must not invoke a TeX engine without a main file")
    }

    @MainActor
    private static func reopeningNestedDocumentsPreservesTheProjectAndDirtyBuffers(in root: URL) async throws {
        let project = try makeProject(in: root, name: "reopen nested documents")
        let chapterDirectory = project.root.appendingPathComponent("sections", isDirectory: true)
        let bibliographyDirectory = project.root.appendingPathComponent("references", isDirectory: true)
        try FileManager.default.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bibliographyDirectory, withIntermediateDirectories: true)
        let chapterURL = chapterDirectory.appendingPathComponent("chapter.tex")
        let bibliographyURL = bibliographyDirectory.appendingPathComponent("library.bib")
        let chapterText = "\\section{Original chapter}\nChapter contents.\n"
        let bibliographyText = "@article{nested,\n  title = {Original reference}\n}\n"
        try chapterText.write(to: chapterURL, atomically: true, encoding: .utf8)
        try bibliographyText.write(to: bibliographyURL, atomically: true, encoding: .utf8)
        let model = AppModel(loadPersistedState: false)
        try await open(project, in: model)
        let workspaceID = model.workspace?.id
        let dirtyMain = project.initialText + "% unsaved main edit\n"
        model.updateEditorText(dirtyMain)

        model.openProjectResource(at: chapterURL)
        try await eventually("the nested chapter to open in the existing project") {
            model.editorFileURL == chapterURL && model.editorText == chapterText && model.canSaveEditorFile
        }
        try require(model.workspace?.id == workspaceID && model.workspace?.mainFileURL == project.source,
                    "Opening a nested chapter must preserve the existing project and its main file")
        let dirtyChapter = chapterText + "% unsaved chapter edit\n"
        model.updateEditorText(dirtyChapter)

        model.openProjectResource(at: bibliographyURL)
        try await eventually("the nested bibliography to open in the existing project") {
            model.editorFileURL == bibliographyURL && model.editorText == bibliographyText && model.canSaveEditorFile
        }
        try require(model.workspace?.id == workspaceID && model.workspace?.rootURL == project.root,
                    "Opening a nested bibliography must not create a project rooted in its subfolder")
        try require(model.workspace?.mainFileURL == project.source, "Opening bibliography text must not replace the existing main file")
        let dirtyBibliography = bibliographyText + "% unsaved bibliography edit\n"
        model.updateEditorText(dirtyBibliography)

        model.openProjectResource(at: chapterURL)
        try await eventually("reopening a chapter to restore its unsaved buffer") {
            model.editorFileURL == chapterURL && model.editorText == dirtyChapter && model.canSaveEditorFile
        }
        try require(!model.isEditorSaved, "Reopening a modified chapter must keep its dirty state")
        model.openProjectResource(at: bibliographyURL)
        try await eventually("reopening a bibliography to restore its unsaved buffer") {
            model.editorFileURL == bibliographyURL && model.editorText == dirtyBibliography && model.canSaveEditorFile
        }
        try require(!model.isEditorSaved, "Reopening a modified bibliography must keep its dirty state")
        model.openProjectResource(at: project.source)
        try await eventually("reopening the main document to retain its earlier unsaved buffer") {
            model.editorFileURL == project.source && model.editorText == dirtyMain && model.canSaveEditorFile
        }
        try require(!model.isEditorSaved && model.workspace?.id == workspaceID && model.workspace?.mainFileURL == project.source,
                    "Repeated file opens must preserve the main document's edits and project identity")
        try require(model.sessions.count == 1, "Nested document opens must not add duplicate sessions")
        try require(model.currentOpenEditorTabs.count == 3 && Set(model.currentOpenEditorTabs).count == 3,
                    "Reopening documents must reuse their existing editor tabs")
        let chapterOnDisk = try String(contentsOf: chapterURL, encoding: .utf8)
        let bibliographyOnDisk = try String(contentsOf: bibliographyURL, encoding: .utf8)
        let mainOnDisk = try String(contentsOf: project.source, encoding: .utf8)
        try require(chapterOnDisk == chapterText && bibliographyOnDisk == bibliographyText && mainOnDisk == project.initialText,
                    "Opening documents must neither save nor discard their unsaved edits")
    }
}
