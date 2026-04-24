import AppKit
import CoreServices
import SwiftUI
import UniformTypeIdentifiers

struct ProjectSidebarView: View {
    var index: ProjectIndex
    var rootURL: URL?
    var mainFileURL: URL?
    var outlineItems: [OutlineItem] = []
    var hidesIntermediateArtifacts: Bool
    var saveStates: [URL: ExplorerSaveState] = [:]
    @Binding var selectedFileURL: URL?
    var onSelectFile: (URL) -> Void
    var onMakeMainFile: (URL) -> Void = { _ in }
    var onMoveFile: (URL, URL) -> Void = { _, _ in }
    var onDeleteFile: (URL) -> Void = { _ in }
    var onRefreshProject: (_ preferredMainFile: URL?, _ preferredSelection: URL?) -> Void
    var onExternalProjectChange: () -> Void
    var onStatus: (String) -> Void

    @State private var tree: [ExplorerNode] = []
    @State private var expanded: Set<URL> = []
    @State private var renamingURL: URL?
    @State private var renameDraft = ""
    @State private var pendingCreation: PendingCreation?
    @State private var creationDraft = ""
    @State private var deleteTarget: URL?
    @State private var dropTarget: URL?
    @State private var directoryMonitor: ProjectDirectoryMonitor?

    var body: some View {
        VStack(spacing: 0) {
            explorerHeader

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let rootURL {
                        FileTreeHeader(rootURL: rootURL, saveState: saveState(for: rootURL))
                            .padding(.horizontal, 16)
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
                            .padding(.horizontal, 16)
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
                            .environment(\.explorerSaveStates, saveStates)
                            .padding(.horizontal, 16)
                        }
                    } else {
                        EmptyExplorerState()
                            .padding(.horizontal, 16)
                    }

                    if !outlineItems.isEmpty {
                        ExplorerSectionHeader(title: "구조")
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        ForEach(outlineItems) { item in
                            Button {
                                onSelectFile(item.location.fileURL)
                            } label: {
                                ExplorerMetadataRow(
                                    title: item.title,
                                    iconName: outlineIconName(for: item.command),
                                    accessory: nil
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.bottom, 18)
            }
        }
        .background(
            ExplorerKeyboardMonitor(
                selectedFileURL: $selectedFileURL,
                beginRename: { url in beginRename(url) },
                requestDelete: { url in deleteTarget = url }
            )
            .frame(width: 0, height: 0)
        )
        .background(ExplorerStyle.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ExplorerStyle.separator)
                .frame(width: 1)
        }
        .clipShape(Rectangle())
        .onAppear {
            reloadTree()
            restartDirectoryMonitor()
        }
        .onDisappear {
            directoryMonitor?.stop()
            directoryMonitor = nil
        }
        .onChange(of: rootURL) { _, _ in
            reloadTree()
            restartDirectoryMonitor()
        }
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

    private var explorerHeader: some View {
        HStack(spacing: 12) {
            Text("프로젝트")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ExplorerStyle.mutedText)

            Spacer()

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
                Image(systemName: "line.3.horizontal.decrease")
            }
            .help("Refresh Explorer")
        }
        .buttonStyle(ExplorerIconButtonStyle())
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func outlineIconName(for command: String) -> String {
        switch command {
        case "section": return "text.alignleft"
        case "subsection": return "text.indent"
        case "paragraph": return "paragraphsign"
        default: return "list.bullet.indent"
        }
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

    private func restartDirectoryMonitor() {
        directoryMonitor?.stop()

        guard let rootURL else {
            directoryMonitor = nil
            return
        }

        let monitor = ProjectDirectoryMonitor(rootURL: rootURL) {
            reloadTree()
            onExternalProjectChange()
        }
        monitor.start()
        directoryMonitor = monitor
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

    private func commitRename(_ url: URL, proposedName: String) {
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
            onMoveFile(url, destination)
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
            onDeleteFile(url)
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

    private func commitCreation(proposedName: String) {
        guard let pendingCreation else { return }
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
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
                onMoveFile(source, destination)
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

    private func saveState(for url: URL) -> ExplorerSaveState {
        Self.saveState(for: url, in: saveStates)
    }

    private static func saveState(for url: URL, in states: [URL: ExplorerSaveState]) -> ExplorerSaveState {
        if let directState = states[url] {
            return directState
        }

        guard url.isDirectory else { return .saved }
        let descendantStates = states.lazy
            .filter { fileURL, _ in fileURL.path.hasPrefix(url.path + "/") }
            .map(\.value)

        if descendantStates.contains(.dirty) {
            return .dirty
        }
        return .saved
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
            commitRename: { _, _ in onStatus("Use the active project explorer to rename files.") },
            cancelRename: {},
            commitCreation: { _ in onStatus("Use the active project explorer to create files.") },
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

private struct ExplorerSaveStatesKey: EnvironmentKey {
    static let defaultValue: [URL: ExplorerSaveState] = [:]
}

private extension EnvironmentValues {
    var explorerSaveStates: [URL: ExplorerSaveState] {
        get { self[ExplorerSaveStatesKey.self] }
        set { self[ExplorerSaveStatesKey.self] = newValue }
    }
}

private struct ExplorerNodeRow: View {
    var node: ExplorerNode
    @Environment(\.explorerSaveStates) private var saveStates
    @Binding var selectedFileURL: URL?
    @Binding var expanded: Set<URL>
    @Binding var dropTarget: URL?
    @Binding var renamingURL: URL?
    @Binding var renameDraft: String
    @Binding var pendingCreation: PendingCreation?
    @Binding var creationDraft: String
    var select: (URL) -> Void
    var rename: (URL) -> Void
    var commitRename: (URL, String) -> Void
    var cancelRename: () -> Void
    var commitCreation: (String) -> Void
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
        HStack(spacing: 10) {
            ExplorerSaveStateDot(state: saveState(for: node.url))

            Image(systemName: node.iconName)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(node.isDirectory ? ExplorerStyle.folderIcon : ExplorerStyle.fileIcon)
                .frame(width: 18)

            if renamingURL == node.url {
                InlineRenameTextField(
                    text: $renameDraft,
                    initialSelectionRange: node.url.renameStemSelectionRange,
                    commit: { proposedName in commitRename(node.url, proposedName) },
                    cancel: cancelRename
                )
                .frame(minWidth: 72, maxWidth: .infinity)
            } else {
                Text(node.url.lastPathComponent)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ExplorerStyle.primaryText)
                    .lineLimit(1)
            }

            if node.url == mainFileURL {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ExplorerStyle.accent)
                    .help("Main file")
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            select(node.url)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if dropTarget == node.url {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ExplorerStyle.dropFill)
        } else if selectedFileURL == node.url {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ExplorerStyle.selectedFill)
        } else {
            Color.clear
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

    private func saveState(for url: URL) -> ExplorerSaveState {
        if let directState = saveStates[url] {
            return directState
        }

        guard url.isDirectory else { return .saved }
        let descendantStates = saveStates.lazy
            .filter { fileURL, _ in fileURL.path.hasPrefix(url.path + "/") }
            .map(\.value)

        if descendantStates.contains(.dirty) {
            return .dirty
        }
        return .saved
    }
}

private struct ExplorerSaveStateDot: View {
    var state: ExplorerSaveState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .frame(width: 12)
            .help(helpText)
    }

    private var color: Color {
        switch state {
        case .dirty:
            return .orange
        case .saved:
            return .green
        }
    }

    private var helpText: String {
        switch state {
        case .dirty:
            return "Modified"
        case .saved:
            return "Saved"
        }
    }
}

private struct ExplorerSectionHeader: View {
    var title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ExplorerStyle.mutedText)
            Spacer()
        }
        .padding(.top, 4)
    }
}

private struct ExplorerMetadataRow: View {
    var title: String
    var iconName: String
    var accessory: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ExplorerStyle.fileIcon)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ExplorerStyle.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let accessory {
                Text(accessory)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ExplorerStyle.mutedText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

private struct EmptyExplorerState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(ExplorerStyle.folderIcon)

            Text("프로젝트를 열어주세요")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ExplorerStyle.primaryText)

            Text("LaTeX 폴더, .tex 파일, 또는 .zip을 열면 여기에 표시됩니다.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(ExplorerStyle.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ExplorerStyle.selectedFill)
        )
    }
}

private struct ExplorerIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ExplorerStyle.iconButton)
            .frame(width: 26, height: 26)
            .background(
                Circle()
                    .fill(configuration.isPressed ? ExplorerStyle.selectedFill : Color.clear)
            )
            .contentShape(Circle())
    }
}

private enum ExplorerStyle {
    static let sidebarBackground = Color(nsColor: .controlBackgroundColor).opacity(0.82)
    static let separator = Color(nsColor: .separatorColor).opacity(0.35)
    static let selectedFill = Color(nsColor: .quaternaryLabelColor).opacity(0.22)
    static let dropFill = Color.accentColor.opacity(0.16)
    static let primaryText = Color(nsColor: .labelColor).opacity(0.86)
    static let mutedText = Color(nsColor: .secondaryLabelColor)
    static let folderIcon = Color(nsColor: .secondaryLabelColor)
    static let fileIcon = Color(nsColor: .tertiaryLabelColor)
    static let iconButton = Color(nsColor: .secondaryLabelColor)
    static let accent = Color.orange.opacity(0.9)
}

private final class ProjectDirectoryMonitor {
    private let rootURL: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "app.texnologia.project-directory-monitor")
    private var stream: FSEventStreamRef?
    private var pendingWorkItem: DispatchWorkItem?

    init(rootURL: URL, onChange: @escaping () -> Void) {
        self.rootURL = rootURL
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let monitor = Unmanaged<ProjectDirectoryMonitor>.fromOpaque(info).takeUnretainedValue()
                monitor.scheduleChange()
            },
            &context,
            [rootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.45,
            flags
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleChange() {
        pendingWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange()
            }
        }

        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
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
    var commit: (String) -> Void
    var cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isDirectory ? "folder.badge.plus" : "doc.badge.plus")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isDirectory ? ExplorerStyle.folderIcon : ExplorerStyle.fileIcon)
                .frame(width: 18)

            InlineRenameTextField(
                text: $draft,
                initialSelectionRange: nil,
                commit: commit,
                cancel: cancel
            )
            .frame(minWidth: 72, maxWidth: .infinity)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ExplorerStyle.selectedFill)
        )
    }
}

private struct InlineRenameTextField: NSViewRepresentable {
    @Binding var text: String
    var initialSelectionRange: NSRange?
    var commit: (String) -> Void
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
        context.coordinator.commit = commit
        context.coordinator.cancel = cancel

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
        context.coordinator.commit = commit
        context.coordinator.cancel = cancel
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var commit: ((String) -> Void)?
        var cancel: (() -> Void)?

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertTab(_:)):
                text = textView.string
                commit?(textView.string)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                cancel?()
                return true
            default:
                return false
            }
        }
    }

    final class RenameNSTextField: NSTextField {
        var onCommit: ((String) -> Void)?
        var onCancel: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 76:
                onCommit?(stringValue)
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
    var saveState: ExplorerSaveState

    var body: some View {
        HStack(spacing: 10) {
            ExplorerSaveStateDot(state: saveState)

            Image(systemName: "folder")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(ExplorerStyle.folderIcon)
                .frame(width: 18)

            Text(rootURL.lastPathComponent)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ExplorerStyle.primaryText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 6)
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
