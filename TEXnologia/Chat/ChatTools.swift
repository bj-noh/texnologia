import Foundation

struct ChatToolOutcome {
    let content: String
    let isError: Bool
}

enum ChatToolRegistry {
    static let toolDefinitions: [LLMToolDef] = [
        LLMToolDef(
            name: "list_project_files",
            description: "List files in the open project. Returns newline-separated relative paths. Optional `subpath` limits listing to a directory.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "subpath": [
                        "type": "string",
                        "description": "Relative path from project root. Defaults to root."
                    ]
                ]
            ]
        ),
        LLMToolDef(
            name: "read_project_file",
            description: "Read the full text content of a file inside the project.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Relative path from project root."
                    ]
                ],
                "required": ["path"]
            ]
        ),
        LLMToolDef(
            name: "write_project_file",
            description: "Overwrite a file inside the project with new content. Creates the file if it does not exist.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Relative path from project root."
                    ],
                    "content": [
                        "type": "string",
                        "description": "Full new file contents."
                    ]
                ],
                "required": ["path", "content"]
            ]
        ),
        LLMToolDef(
            name: "replace_in_file",
            description: "Replace an exact string inside a file with a new string. Fails unless `old_string` appears exactly once.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string"],
                    "old_string": ["type": "string"],
                    "new_string": ["type": "string"]
                ],
                "required": ["path", "old_string", "new_string"]
            ]
        ),
        LLMToolDef(
            name: "apply_to_open_editor",
            description: "Propose an edit to the currently open editor. The user reviews the change hunk-by-hunk in an inline review UI (accept / manually-edit / reject) before it is applied to the buffer. Always provide the full proposed file contents.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "content": [
                        "type": "string",
                        "description": "Full replacement text for the open editor. Will be staged as a reviewable proposal, not applied directly."
                    ]
                ],
                "required": ["content"]
            ]
        )
    ]

    static func execute(name: String, inputJSON: String, appModel: AppModel) async -> ChatToolOutcome {
        let data = Data(inputJSON.utf8)
        let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        switch name {
        case "list_project_files":
            return await MainActor.run { listFiles(input: input, appModel: appModel) }
        case "read_project_file":
            return await MainActor.run { readFile(input: input, appModel: appModel) }
        case "write_project_file":
            return await MainActor.run { writeFile(input: input, appModel: appModel) }
        case "replace_in_file":
            return await MainActor.run { replaceInFile(input: input, appModel: appModel) }
        case "apply_to_open_editor":
            return await MainActor.run { applyToOpenEditor(input: input, appModel: appModel) }
        default:
            return ChatToolOutcome(content: "Unknown tool: \(name)", isError: true)
        }
    }

    // MARK: - Implementations (MainActor)

    @MainActor
    private static func listFiles(input: [String: Any], appModel: AppModel) -> ChatToolOutcome {
        guard let root = appModel.workspace?.rootURL else {
            return ChatToolOutcome(content: "No project is open.", isError: true)
        }
        let subpath = input["subpath"] as? String ?? ""
        let target = subpath.isEmpty ? root : root.appendingPathComponent(subpath)
        guard target.path.hasPrefix(root.path) else {
            return ChatToolOutcome(content: "Path is outside the project root.", isError: true)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: target,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return ChatToolOutcome(content: "Failed to enumerate directory.", isError: true)
        }

        var paths: [String] = []
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            paths.append(relative)
        }
        paths.sort()
        let capped = paths.prefix(500)
        let truncated = paths.count > capped.count ? "\n… (\(paths.count - capped.count) more)" : ""
        return ChatToolOutcome(content: capped.joined(separator: "\n") + truncated, isError: false)
    }

    @MainActor
    private static func readFile(input: [String: Any], appModel: AppModel) -> ChatToolOutcome {
        guard let root = appModel.workspace?.rootURL else {
            return ChatToolOutcome(content: "No project is open.", isError: true)
        }
        guard let relative = input["path"] as? String, !relative.isEmpty else {
            return ChatToolOutcome(content: "`path` is required.", isError: true)
        }
        let url = root.appendingPathComponent(relative)
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path) else {
            return ChatToolOutcome(content: "Path is outside the project root.", isError: true)
        }
        do {
            let data = try Data(contentsOf: url)
            if data.count > 512_000 {
                return ChatToolOutcome(content: "File is too large to read in full (> 500KB).", isError: true)
            }
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            return ChatToolOutcome(content: text, isError: false)
        } catch {
            return ChatToolOutcome(content: "Read failed: \(error.localizedDescription)", isError: true)
        }
    }

    @MainActor
    private static func writeFile(input: [String: Any], appModel: AppModel) -> ChatToolOutcome {
        guard let root = appModel.workspace?.rootURL else {
            return ChatToolOutcome(content: "No project is open.", isError: true)
        }
        guard let relative = input["path"] as? String, !relative.isEmpty else {
            return ChatToolOutcome(content: "`path` is required.", isError: true)
        }
        guard let content = input["content"] as? String else {
            return ChatToolOutcome(content: "`content` is required.", isError: true)
        }
        let url = root.appendingPathComponent(relative)
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path) else {
            return ChatToolOutcome(content: "Path is outside the project root.", isError: true)
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.data(using: .utf8)?.write(to: url, options: [.atomic])
            appModel.refreshProjectFromDisk()
            if appModel.editorFileURL == url {
                appModel.updateEditorText(content)
            }
            return ChatToolOutcome(content: "Wrote \(relative) (\(content.count) chars).", isError: false)
        } catch {
            return ChatToolOutcome(content: "Write failed: \(error.localizedDescription)", isError: true)
        }
    }

    @MainActor
    private static func replaceInFile(input: [String: Any], appModel: AppModel) -> ChatToolOutcome {
        guard let root = appModel.workspace?.rootURL else {
            return ChatToolOutcome(content: "No project is open.", isError: true)
        }
        guard let relative = input["path"] as? String, !relative.isEmpty else {
            return ChatToolOutcome(content: "`path` is required.", isError: true)
        }
        guard let oldString = input["old_string"] as? String,
              let newString = input["new_string"] as? String else {
            return ChatToolOutcome(content: "`old_string` and `new_string` are required.", isError: true)
        }
        let url = root.appendingPathComponent(relative)
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path) else {
            return ChatToolOutcome(content: "Path is outside the project root.", isError: true)
        }

        do {
            let data = try Data(contentsOf: url)
            guard var text = String(data: data, encoding: .utf8) else {
                return ChatToolOutcome(content: "File is not UTF-8 text.", isError: true)
            }
            let occurrences = text.components(separatedBy: oldString).count - 1
            guard occurrences == 1 else {
                return ChatToolOutcome(
                    content: "`old_string` must appear exactly once (found \(occurrences)).",
                    isError: true
                )
            }
            text = text.replacingOccurrences(of: oldString, with: newString)
            try text.data(using: .utf8)?.write(to: url, options: [.atomic])
            appModel.refreshProjectFromDisk()
            if appModel.editorFileURL == url {
                appModel.updateEditorText(text)
            }
            return ChatToolOutcome(content: "Replaced 1 occurrence in \(relative).", isError: false)
        } catch {
            return ChatToolOutcome(content: "Replace failed: \(error.localizedDescription)", isError: true)
        }
    }

    @MainActor
    private static func applyToOpenEditor(input: [String: Any], appModel: AppModel) -> ChatToolOutcome {
        guard let content = input["content"] as? String else {
            return ChatToolOutcome(content: "`content` is required.", isError: true)
        }
        guard appModel.editorFileURL != nil else {
            return ChatToolOutcome(content: "No file is currently open in the editor.", isError: true)
        }
        guard let edit = appModel.stagePendingEdit(proposedText: content) else {
            return ChatToolOutcome(
                content: "Proposal is identical to the current buffer - nothing to review.",
                isError: false
            )
        }
        let count = edit.hunks.count
        return ChatToolOutcome(
            content: "Staged \(count) change\(count == 1 ? "" : "s") for inline review. The user will accept, edit, or reject each hunk before it's applied.",
            isError: false
        )
    }
}
