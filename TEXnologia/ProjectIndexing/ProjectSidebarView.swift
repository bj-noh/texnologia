import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectSidebarView: View {
    var index: ProjectIndex
    var rootURL: URL?
    var mainFileURL: URL?
    var hidesIntermediateArtifacts: Bool
    @Binding var selectedFileURL: URL?
    var onSelectFile: (URL) -> Void
    var onMakeMainFile: (URL) -> Void = { _ in }
    var onRefreshProject: (_ preferredMainFile: URL?, _ preferredSelection: URL?) -> Void
    var onStatus: (String) -> Void

    @State private var tree: [ExplorerNode] = []
    @State private var expanded: Set<URL> = []
    @State private var renamingURL: URL?
    @State private var renameDraft = ""
    @State private var pendingCreation: PendingCreation?
    @State private var creationDraft = ""
    @State private var deleteTarget: URL?
    @State private var dropTarget: URL?

    var body: some View {
        VStack(spacing: 0) {
            utilityBar

            List(selection: $selectedFileURL) {
                Section("Explorer") {
                    if let rootURL {
                        FileTreeHeader(rootURL: rootURL)
                            .contextMenu {
                                projectContextMenu(for: rootURL)
                            }
                            .onDrop(of: [.fileURL], isTargeted: dropBinding(for: rootURL)) { providers in
                                handleDrop(providers, into: rootURL)
                            }

                        if pendingCreation?.directory == rootURL {
                            PendingCreationRow(
                                draft: $creationDraft,
                                isDirectory: pendingCreation?.isDirectory == true,
                                commit: commitCreation,
                                cancel: cancelCreation
                            )
                        }

                        ForEach(tree) { node in
                            ExplorerNodeRow(
                                node: node,
                                selectedFileURL: $selectedFileURL,
                                expanded: $expanded,
                                dropTarget: $dropTarget,
                                renamingURL: $renamingURL,
                                renameDraft: $renameDraft,
                                pendingCreation: $pendingCreation,
                                creationDraft: $creationDraft,
                                select: select,
                                rename: beginRename,
                                commitRename: commitRename,
                                cancelRename: cancelRename,
                                commitCreation: commitCreation,
                                cancelCreation: cancelCreation,
                                delete: { deleteTarget = $0 },
                                reveal: revealInFinder,
                                createFile: beginCreateFile,
                                createFolder: createFolder,
                                makeMain: onMakeMainFile,
                                mainFileURL: mainFileURL,
                                handleDrop: handleDrop
                            )
                        }
                    } else {
                        Text("Open a project to browse files.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Outline") {
                    ForEach(index.outline) { item in
                        Button {
                            onSelectFile(item.location.fileURL)
                        } label: {
                            Text(item.title)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Citations") {
                    ForEach(index.citationKeys, id: \.self) { key in
                        Text(key)
                            .lineLimit(1)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(
            ExplorerKeyboardMonitor(
                selectedFileURL: $selectedFileURL,
                beginRename: { url in beginRename(url) },
                requestDelete: { url in deleteTarget = url }
            )
            .frame(width: 0, height: 0)
        )
        .background(.thinMaterial)
        .clipShape(Rectangle())
        .onAppear(perform: reloadTree)
        .onChange(of: rootURL) { _, _ in reloadTree() }
        .onChange(of: index.texFiles) { _, _ in reloadTree() }
        .alert("Delete File?", isPresented: deleteConfirmationBinding) {
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
            Button("Delete", role: .destructive) {
                if let deleteTarget {
                    deletePermanently(deleteTarget)
                }
                deleteTarget = nil
            }
        } message: {
            Text(deleteTarget.map { "This will permanently delete '\($0.lastPathComponent)' from disk and update the project explorer." } ?? "")
        }
    }

    private var utilityBar: some View {
        HStack(spacing: 6) {
            Button {
                beginCreateFile(in: selectedDirectoryURL())
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help("New File")

            Button {
                createFolder(in: selectedDirectoryURL())
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("New Folder")

            Button {
                reloadTree()
                onRefreshProject(nil, selectedFileURL)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh Explorer")

            Spacer()

            Button {
                if let selectedFileURL {
                    revealInFinder(selectedFileURL)
                } else if let rootURL {
                    revealInFinder(rootURL)
                }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Reveal in Finder")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func projectContextMenu(for rootURL: URL) -> some View {
        Button("New File") { beginCreateFile(in: rootURL) }
        Button("New Folder") { createFolder(in: rootURL) }
        Divider()
        Button("Reveal in Finder") { revealInFinder(rootURL) }
        Button("Refresh") {
            reloadTree()
            onRefreshProject(nil, selectedFileURL)
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private func reloadTree() {
        guard let rootURL else {
            tree = []
            return
        }

        tree = ExplorerTreeBuilder(hidesIntermediateArtifacts: hidesIntermediateArtifacts).children(of: rootURL)
        expanded.insert(rootURL)
    }

    private func select(_ url: URL) {
        guard !url.isDirectory else {
            if expanded.contains(url) {
                expanded.remove(url)
            } else {
                expanded.insert(url)
            }
            return
        }

        selectedFileURL = url
        onSelectFile(url)
    }

    private func beginRename(_ url: URL) {
        pendingCreation = nil
        creationDraft = ""
        renamingURL = url
        renameDraft = url.lastPathComponent
    }

    private func commitRename(_ url: URL) {
        let proposedName = renameDraft
        renamingURL = nil
        renameDraft = ""
        rename(url, to: proposedName)
    }

    private func cancelRename() {
        renamingURL = nil
        renameDraft = ""
    }

    private func rename(_ url: URL, to proposedName: String) {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != url.lastPathComponent else { return }
        guard !trimmed.contains("/") else {
            onStatus("File names cannot contain '/'.")
            return
        }

        let destination = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            onStatus("A file named \(trimmed) already exists.")
            return
        }

        do {
            try FileManager.default.moveItem(at: url, to: destination)
            selectedFileURL = selectedFileURL == url ? destination : selectedFileURL
            reloadTree()
            onRefreshProject(nil, selectedFileURL)
            onStatus("Renamed \(url.lastPathComponent) to \(trimmed).")
        } catch {
            onStatus("Rename failed: \(error.localizedDescription)")
        }
    }

    private func deletePermanently(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            if selectedFileURL == url || selectedFileURL?.path.hasPrefix(url.path + "/") == true {
                selectedFileURL = nil
            }
            reloadTree()
            onRefreshProject(nil, selectedFileURL)
            onStatus("Deleted \(url.lastPathComponent).")
        } catch {
            onStatus("Delete failed: \(error.localizedDescription)")
        }
    }

    private func beginCreateFile(in directory: URL) {
        beginCreation(in: directory, isDirectory: false)
    }

    private func createFolder(in directory: URL) {
        beginCreation(in: directory, isDirectory: true)
    }

    private func beginCreation(in directory: URL, isDirectory: Bool) {
        renamingURL = nil
        renameDraft = ""
        pendingCreation = PendingCreation(directory: directory, isDirectory: isDirectory)
        creationDraft = ""
        expanded.insert(directory)
    }

    private func commitCreation() {
        guard let pendingCreation else { return }
        let trimmed = creationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelCreation()
            return
        }
        guard !trimmed.contains("/") else {
            onStatus("File names cannot contain '/'.")
            return
        }

        createItem(named: trimmed, in: pendingCreation.directory, isDirectory: pendingCreation.isDirectory)
    }

    private func cancelCreation() {
        pendingCreation = nil
        creationDraft = ""
    }

    private func createItem(named baseName: String, in directory: URL, isDirectory: Bool) {
        let destination = uniqueDestination(for: directory.appendingPathComponent(baseName))

        do {
            if isDirectory {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                expanded.insert(destination)
            } else {
                try Data().write(to: destination, options: .atomic)
                selectedFileURL = destination
            }

            pendingCreation = nil
            creationDraft = ""
            expanded.insert(directory)
            reloadTree()
            onRefreshProject(nil, isDirectory ? selectedFileURL : destination)
            onStatus("Created \(destination.lastPathComponent).")
        } catch {
            onStatus("Create failed: \(error.localizedDescription)")
        }
    }

    private func selectedDirectoryURL() -> URL {
        guard let rootURL else {
            return URL(fileURLWithPath: NSHomeDirectory())
        }

        guard let selectedFileURL else {
            return rootURL
        }

        return selectedFileURL.isDirectory ? selectedFileURL : selectedFileURL.deletingLastPathComponent()
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func dropBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { dropTarget == url },
            set: { isTargeted in dropTarget = isTargeted ? url : nil }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider], into target: URL) -> Bool {
        let destinationDirectory = target.isDirectory ? target : target.deletingLastPathComponent()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let source = Self.fileURL(from: item) else { return }
                DispatchQueue.main.async {
                    moveOrCopy(source, into: destinationDirectory)
                }
            }
            return true
        }

        return false
    }

    private func moveOrCopy(_ source: URL, into destinationDirectory: URL) {
        guard let rootURL else { return }
        guard source != destinationDirectory else { return }

        if destinationDirectory.path.hasPrefix(source.path + "/") {
            onStatus("Cannot move a folder into itself.")
            return
        }

        let destination = uniqueDestination(for: destinationDirectory.appendingPathComponent(source.lastPathComponent))

        do {
            if source.path.hasPrefix(rootURL.path + "/") {
                try FileManager.default.moveItem(at: source, to: destination)
                onStatus("Moved \(source.lastPathComponent).")
            } else {
                if source.isDirectory {
                    try FileManager.default.copyItem(at: source, to: destination)
                } else {
                    try FileManager.default.copyItem(at: source, to: destination)
                }
                onStatus("Copied \(source.lastPathComponent) into the project.")
            }

            selectedFileURL = selectedFileURL == source ? destination : selectedFileURL
            expanded.insert(destinationDirectory)
            reloadTree()
            onRefreshProject(nil, selectedFileURL)
        } catch {
            onStatus("Drop failed: \(error.localizedDescription)")
        }
    }

    private func uniqueDestination(for proposedURL: URL) -> URL {
        guard FileManager.default.fileExists(atPath: proposedURL.path) else {
            return proposedURL
        }

        let directory = proposedURL.deletingLastPathComponent()
        let base = proposedURL.deletingPathExtension().lastPathComponent
        let ext = proposedURL.pathExtension

        for index in 2...999 {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent("\(base) \(UUID().uuidString).\(ext)")
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
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

struct ProjectSessionsSidebarView: View {
    var sessions: [WorkspaceSession]
    var activeWorkspaceID: WorkspaceID?
    var hidesIntermediateArtifacts: Bool
    @Binding var selectedFileURL: URL?
    var onActivateSession: (WorkspaceID) -> Void
    var onSelectFile: (URL) -> Void
    var onMakeMainFile: (URL) -> Void
    var onStatus: (String) -> Void

    @State private var trees: [WorkspaceID: [ExplorerNode]] = [:]
    @State private var expanded: Set<URL> = []
    @State private var dropTarget: URL?
    @State private var renamingURL: URL?
    @State private var renameDraft = ""
    @State private var pendingCreation: PendingCreation?
    @State private var creationDraft = ""

    var body: some View {
        List(selection: $selectedFileURL) {
            Section("Sessions") {
                ForEach(sessions) { session in
                    sessionDisclosure(session)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.thinMaterial)
        .onAppear(perform: reload)
        .onChange(of: sessions) { _, _ in reload() }
    }

    private func sessionDisclosure(_ session: WorkspaceSession) -> some View {
        DisclosureGroup(isExpanded: expandedBinding(for: session.workspace.rootURL)) {
            ForEach(trees[session.id] ?? []) { node in
                sessionNode(node, session: session)
            }
        } label: {
            sessionHeader(session)
        }
        .contextMenu {
            Button("Activate Session") { onActivateSession(session.id) }
            Button("Reveal in Finder") { revealInFinder(session.workspace.rootURL) }
        }
    }

    private func sessionNode(_ node: ExplorerNode, session: WorkspaceSession) -> some View {
        ExplorerNodeRow(
            node: node,
            selectedFileURL: $selectedFileURL,
            expanded: $expanded,
            dropTarget: $dropTarget,
            renamingURL: $renamingURL,
            renameDraft: $renameDraft,
            pendingCreation: $pendingCreation,
            creationDraft: $creationDraft,
            select: { url in
                onActivateSession(session.id)
                onSelectFile(url)
            },
            rename: { _ in onStatus("Use the active project explorer to rename files.") },
            commitRename: { _ in onStatus("Use the active project explorer to rename files.") },
            cancelRename: {},
            commitCreation: { onStatus("Use the active project explorer to create files.") },
            cancelCreation: {},
            delete: { _ in onStatus("Use the active project explorer to delete files.") },
            reveal: revealInFinder,
            createFile: { _ in onStatus("Use the active project explorer to create files.") },
            createFolder: { _ in onStatus("Use the active project explorer to create folders.") },
            makeMain: onMakeMainFile,
            mainFileURL: session.workspace.mainFileURL,
            handleDrop: { _, _ in
                onStatus("Use the active project explorer for drag and drop changes.")
                return false
            }
        )
    }

    private func sessionHeader(_ session: WorkspaceSession) -> some View {
        HStack(spacing: 6) {
            Image(systemName: session.id == activeWorkspaceID ? "shippingbox.fill" : "shippingbox")
                .foregroundStyle(session.id == activeWorkspaceID ? Color.accentColor : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.workspace.displayName)
                    .fontWeight(session.id == activeWorkspaceID ? .semibold : .regular)
                    .lineLimit(1)
                Text(session.workspace.mainFileURL?.lastPathComponent ?? "No main file")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onActivateSession(session.id)
        }
    }

    private func reload() {
        var next: [WorkspaceID: [ExplorerNode]] = [:]
        for session in sessions {
            next[session.id] = ExplorerTreeBuilder(hidesIntermediateArtifacts: hidesIntermediateArtifacts)
                .children(of: session.workspace.rootURL)
            expanded.insert(session.workspace.rootURL)
        }
        trees = next
    }

    private func expandedBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(url) },
            set: { isExpanded in
                if isExpanded {
                    expanded.insert(url)
                } else {
                    expanded.remove(url)
                }
            }
        )
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct ExplorerNodeRow: View {
    var node: ExplorerNode
    @Binding var selectedFileURL: URL?
    @Binding var expanded: Set<URL>
    @Binding var dropTarget: URL?
    @Binding var renamingURL: URL?
    @Binding var renameDraft: String
    @Binding var pendingCreation: PendingCreation?
    @Binding var creationDraft: String
    var select: (URL) -> Void
    var rename: (URL) -> Void
    var commitRename: (URL) -> Void
    var cancelRename: () -> Void
    var commitCreation: () -> Void
    var cancelCreation: () -> Void
    var delete: (URL) -> Void
    var reveal: (URL) -> Void
    var createFile: (URL) -> Void
    var createFolder: (URL) -> Void
    var makeMain: (URL) -> Void = { _ in }
    var mainFileURL: URL? = nil
    var handleDrop: ([NSItemProvider], URL) -> Bool

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(node.children) { child in
                    ExplorerNodeRow(
                        node: child,
                        selectedFileURL: $selectedFileURL,
                        expanded: $expanded,
                        dropTarget: $dropTarget,
                        renamingURL: $renamingURL,
                        renameDraft: $renameDraft,
                        pendingCreation: $pendingCreation,
                        creationDraft: $creationDraft,
                        select: select,
                        rename: rename,
                        commitRename: commitRename,
                        cancelRename: cancelRename,
                        commitCreation: commitCreation,
                        cancelCreation: cancelCreation,
                        delete: delete,
                        reveal: reveal,
                        createFile: createFile,
                        createFolder: createFolder,
                        makeMain: makeMain,
                        mainFileURL: mainFileURL,
                        handleDrop: handleDrop
                    )
                }

                if pendingCreation?.directory == node.url {
                    PendingCreationRow(
                        draft: $creationDraft,
                        isDirectory: pendingCreation?.isDirectory == true,
                        commit: commitCreation,
                        cancel: cancelCreation
                    )
                }
            } label: {
                rowLabel
            }
            .contextMenu { contextMenu }
            .onDrag { NSItemProvider(object: node.url as NSURL) }
            .onDrop(of: [.fileURL], isTargeted: dropBinding) { providers in
                handleDrop(providers, node.url)
            }
        } else {
            rowLabel
                .tag(Optional(node.url))
                .contextMenu { contextMenu }
                .onDrag { NSItemProvider(object: node.url as NSURL) }
                .onChange(of: selectedFileURL) { _, newValue in
                    guard newValue == node.url else { return }
                    select(node.url)
                }
                .onDrop(of: [.fileURL], isTargeted: dropBinding) { providers in
                    handleDrop(providers, node.url)
                }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: node.iconName)
                .foregroundStyle(node.isDirectory ? .blue : .secondary)
                .frame(width: 16)

            if renamingURL == node.url {
                InlineRenameTextField(
                    text: $renameDraft,
                    initialSelectionRange: node.url.renameStemSelectionRange,
                    commit: { commitRename(node.url) },
                    cancel: cancelRename
                )
                .frame(minWidth: 72, maxWidth: .infinity)
            } else {
                Text(node.url.lastPathComponent)
                    .lineLimit(1)
            }

            if node.url == mainFileURL {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .help("Main file")
            }
            Spacer()
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .background(dropTarget == node.url ? Color.accentColor.opacity(0.18) : Color.clear)
        .onTapGesture {
            select(node.url)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if node.isDirectory {
            Button("New File") { createFile(node.url) }
            Button("New Folder") { createFolder(node.url) }
            Divider()
        }

        if !node.isDirectory && node.url.pathExtension.lowercased() == "tex" {
            Button("Use as Main File") { makeMain(node.url) }
            Divider()
        }

        Button("Rename") { rename(node.url) }
        Button("Reveal in Finder") { reveal(node.url) }
        Divider()
        Button("Delete", role: .destructive) { delete(node.url) }
    }

    private var expandedBinding: Binding<Bool> {
        Binding(
            get: { expanded.contains(node.url) },
            set: { isExpanded in
                if isExpanded {
                    expanded.insert(node.url)
                } else {
                    expanded.remove(node.url)
                }
            }
        )
    }

    private var dropBinding: Binding<Bool> {
        Binding(
            get: { dropTarget == node.url },
            set: { isTargeted in dropTarget = isTargeted ? node.url : nil }
        )
    }
}

private struct PendingCreation: Identifiable, Hashable {
    let id = UUID()
    var directory: URL
    var isDirectory: Bool
}

private struct PendingCreationRow: View {
    @Binding var draft: String
    var isDirectory: Bool
    var commit: () -> Void
    var cancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isDirectory ? "folder.badge.plus" : "doc.badge.plus")
                .foregroundStyle(isDirectory ? .blue : .secondary)
                .frame(width: 16)

            InlineRenameTextField(
                text: $draft,
                initialSelectionRange: nil,
                commit: commit,
                cancel: cancel
            )
            .frame(minWidth: 72, maxWidth: .infinity)

            Spacer()
        }
        .padding(.vertical, 1)
    }
}

private struct InlineRenameTextField: NSViewRepresentable {
    @Binding var text: String
    var initialSelectionRange: NSRange?
    var commit: () -> Void
    var cancel: () -> Void

    func makeNSView(context: Context) -> RenameNSTextField {
        let textField = RenameNSTextField()
        textField.isBordered = true
        textField.isBezeled = true
        textField.drawsBackground = true
        textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        textField.stringValue = text
        textField.onCommit = commit
        textField.onCancel = cancel
        textField.delegate = context.coordinator

        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
            if let initialSelectionRange {
                textField.currentEditor()?.selectedRange = initialSelectionRange
            } else {
                textField.currentEditor()?.selectAll(nil)
            }
        }

        return textField
    }

    func updateNSView(_ textField: RenameNSTextField, context: Context) {
        textField.onCommit = commit
        textField.onCancel = cancel
        textField.delegate = context.coordinator
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }
    }

    final class RenameNSTextField: NSTextField {
        var onCommit: (() -> Void)?
        var onCancel: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 76:
                onCommit?()
            case 53:
                onCancel?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}

private struct ExplorerKeyboardMonitor: NSViewRepresentable {
    @Binding var selectedFileURL: URL?
    var beginRename: (URL) -> Void
    var requestDelete: (URL) -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.selectedFileURL = selectedFileURL
        context.coordinator.beginRename = beginRename
        context.coordinator.requestDelete = requestDelete
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedFileURL: selectedFileURL,
            beginRename: beginRename,
            requestDelete: requestDelete
        )
    }

    final class Coordinator {
        var selectedFileURL: URL?
        var beginRename: (URL) -> Void
        var requestDelete: (URL) -> Void
        private var monitor: Any?

        init(selectedFileURL: URL?, beginRename: @escaping (URL) -> Void, requestDelete: @escaping (URL) -> Void) {
            self.selectedFileURL = selectedFileURL
            self.beginRename = beginRename
            self.requestDelete = requestDelete
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let selectedFileURL else { return event }
                guard !Self.isTextInputActive else { return event }

                switch event.keyCode {
                case 36, 76:
                    beginRename(selectedFileURL)
                    return nil
                case 51, 117:
                    requestDelete(selectedFileURL)
                    return nil
                default:
                    return event
                }
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private static var isTextInputActive: Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else { return false }
            return responder is NSTextView || responder is NSTextField
        }
    }
}

private struct FileTreeHeader: View {
    var rootURL: URL

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(rootURL.lastPathComponent)
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct ExplorerNode: Identifiable, Hashable {
    var id: URL { url }
    var url: URL
    var isDirectory: Bool
    var children: [ExplorerNode]

    var iconName: String {
        if isDirectory {
            return "folder"
        }

        switch url.pathExtension.lowercased() {
        case "tex": return "doc.plaintext"
        case "bib": return "quote.bubble"
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "eps": return "photo"
        case "sty", "cls": return "curlybraces"
        case "zip": return "archivebox"
        default: return "doc"
        }
    }
}

private struct ExplorerTreeBuilder {
    var hidesIntermediateArtifacts: Bool

    func children(of directory: URL) -> [ExplorerNode] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter(shouldDisplay)
            .map(node)
            .sorted(by: sort)
    }

    private func node(for url: URL) -> ExplorerNode {
        let isDirectory = url.isDirectory
        return ExplorerNode(
            url: url,
            isDirectory: isDirectory,
            children: isDirectory ? children(of: url) : []
        )
    }

    private func shouldDisplay(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if hidesIntermediateArtifacts && (name == ".texnologia-build" || name == ".paperforge-build") { return false }
        if name == ".DS_Store" { return false }
        return true
    }

    private func sort(_ lhs: ExplorerNode, _ rhs: ExplorerNode) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }
        return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent) == .orderedAscending
    }
}

private extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    var renameStemSelectionRange: NSRange? {
        guard !isDirectory, !pathExtension.isEmpty else {
            return nil
        }
        return NSRange(location: 0, length: deletingPathExtension().lastPathComponent.count)
    }
}
