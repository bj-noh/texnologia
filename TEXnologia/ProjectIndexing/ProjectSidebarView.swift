import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectSidebarView: View {
    var index: ProjectIndex
    var rootURL: URL?
    var hidesIntermediateArtifacts: Bool
    @Binding var selectedFileURL: URL?
    var onSelectFile: (URL) -> Void
    var onRefreshProject: (_ preferredMainFile: URL?, _ preferredSelection: URL?) -> Void
    var onStatus: (String) -> Void

    @State private var tree: [ExplorerNode] = []
    @State private var expanded: Set<URL> = []
    @State private var renameRequest: RenameRequest?
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

                        ForEach(tree) { node in
                            ExplorerNodeRow(
                                node: node,
                                selectedFileURL: $selectedFileURL,
                                expanded: $expanded,
                                dropTarget: $dropTarget,
                                select: select,
                                rename: beginRename,
                                delete: { deleteTarget = $0 },
                                reveal: revealInFinder,
                                createFile: createTexFile,
                                createFolder: createFolder,
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
        .background(.thinMaterial)
        .clipShape(Rectangle())
        .onAppear(perform: reloadTree)
        .onChange(of: rootURL) { _, _ in reloadTree() }
        .onChange(of: index.texFiles) { _, _ in reloadTree() }
        .sheet(item: $renameRequest) { request in
            RenameSheet(request: request) { newName in
                rename(request.url, to: newName)
            }
        }
        .alert("Move to Trash?", isPresented: deleteConfirmationBinding) {
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
            Button("Move to Trash", role: .destructive) {
                if let deleteTarget {
                    moveToTrash(deleteTarget)
                }
                deleteTarget = nil
            }
        } message: {
            Text(deleteTarget.map { "This will move '\($0.lastPathComponent)' to the macOS Trash and update the project explorer." } ?? "")
        }
    }

    private var utilityBar: some View {
        HStack(spacing: 6) {
            Button {
                createTexFile(in: selectedDirectoryURL())
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help("New TeX File")

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
        Button("New TeX File") { createTexFile(in: rootURL) }
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
        renameRequest = RenameRequest(url: url, initialName: url.lastPathComponent)
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

    private func moveToTrash(_ url: URL) {
        do {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
            if selectedFileURL == url || selectedFileURL?.path.hasPrefix(url.path + "/") == true {
                selectedFileURL = nil
            }
            reloadTree()
            onRefreshProject(nil, selectedFileURL)
            onStatus("Moved \(url.lastPathComponent) to Trash.")
        } catch {
            onStatus("Delete failed: \(error.localizedDescription)")
        }
    }

    private func createTexFile(in directory: URL) {
        createItem(named: "untitled.tex", in: directory, isDirectory: false)
    }

    private func createFolder(in directory: URL) {
        createItem(named: "New Folder", in: directory, isDirectory: true)
    }

    private func createItem(named baseName: String, in directory: URL, isDirectory: Bool) {
        let destination = uniqueDestination(for: directory.appendingPathComponent(baseName))

        do {
            if isDirectory {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                expanded.insert(destination)
            } else {
                try "\\section{New Section}\n".write(to: destination, atomically: true, encoding: .utf8)
                selectedFileURL = destination
            }

            expanded.insert(directory)
            reloadTree()
            onRefreshProject(nil, isDirectory ? selectedFileURL : destination)
            beginRename(destination)
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

private struct ExplorerNodeRow: View {
    var node: ExplorerNode
    @Binding var selectedFileURL: URL?
    @Binding var expanded: Set<URL>
    @Binding var dropTarget: URL?
    var select: (URL) -> Void
    var rename: (URL) -> Void
    var delete: (URL) -> Void
    var reveal: (URL) -> Void
    var createFile: (URL) -> Void
    var createFolder: (URL) -> Void
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
                        select: select,
                        rename: rename,
                        delete: delete,
                        reveal: reveal,
                        createFile: createFile,
                        createFolder: createFolder,
                        handleDrop: handleDrop
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
            Text(node.url.lastPathComponent)
                .lineLimit(1)
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
            Button("New TeX File") { createFile(node.url) }
            Button("New Folder") { createFolder(node.url) }
            Divider()
        }

        Button("Rename") { rename(node.url) }
        Button("Reveal in Finder") { reveal(node.url) }
        Divider()
        Button("Move to Trash", role: .destructive) { delete(node.url) }
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

private struct RenameSheet: View {
    var request: RenameRequest
    var onCommit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(request: RenameRequest, onCommit: @escaping (String) -> Void) {
        self.request = request
        self.onCommit = onCommit
        self._name = State(initialValue: request.initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename")
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Rename") {
                    onCommit(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}

private struct RenameRequest: Identifiable {
    var id: URL { url }
    var url: URL
    var initialName: String
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
}
