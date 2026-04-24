import Foundation
import SwiftUI

@MainActor
final class ChatSession: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isStreaming: Bool = false
    @Published var statusMessage: String?
    @Published var lastError: String?

    private unowned let appModel: AppModel
    private var pendingTask: Task<Void, Never>?

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var isConfigured: Bool { appModel.settings.llm.isConfigured }

    func clear() {
        messages.removeAll()
        statusMessage = nil
        lastError = nil
    }

    func send(userText: String) {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard isConfigured else {
            lastError = "Set an API key first."
            return
        }

        messages.append(ChatMessage(role: .user, blocks: [.text(trimmed)]))
        runAgenticLoop()
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        isStreaming = false
        statusMessage = "Cancelled"
    }

    private func runAgenticLoop() {
        pendingTask?.cancel()
        isStreaming = true
        statusMessage = "Thinking…"
        lastError = nil

        let config = appModel.settings.llm
        let systemPrompt = makeSystemPrompt()
        let tools = ChatToolRegistry.toolDefinitions

        pendingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try LLMClientFactory.make(for: config)
                var iteration = 0
                while iteration < 8 {
                    iteration += 1
                    let response = try await client.send(
                        messages: self.messages,
                        tools: tools,
                        system: systemPrompt
                    )

                    try Task.checkCancellation()
                    let assistantMessage = self.appendAssistantBlocks(response.blocks)
                    let toolCalls = assistantMessage.toolCalls

                    if toolCalls.isEmpty {
                        self.statusMessage = nil
                        self.isStreaming = false
                        return
                    }

                    self.statusMessage = "Running tools: \(toolCalls.map(\.name).joined(separator: ", "))"

                    var resultBlocks: [ChatBlock] = []
                    for call in toolCalls {
                        try Task.checkCancellation()
                        let outcome = await ChatToolRegistry.execute(
                            name: call.name,
                            inputJSON: call.inputJSON,
                            appModel: self.appModel
                        )
                        resultBlocks.append(.toolResult(ChatToolResult(
                            toolUseID: call.id,
                            content: outcome.content,
                            isError: outcome.isError
                        )))
                    }
                    self.messages.append(ChatMessage(role: .user, blocks: resultBlocks))
                    self.statusMessage = "Generating response…"
                }
                self.statusMessage = "Reached the tool iteration limit."
                self.isStreaming = false
            } catch is CancellationError {
                self.isStreaming = false
                self.statusMessage = nil
            } catch {
                self.lastError = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                self.isStreaming = false
                self.statusMessage = nil
            }
        }
    }

    private func appendAssistantBlocks(_ blocks: [LLMResponse.Block]) -> ChatMessage {
        let chatBlocks: [ChatBlock] = blocks.map { block in
            switch block {
            case .text(let text): return .text(text)
            case .toolCall(let id, let name, let input):
                return .toolCall(ChatToolCall(id: id, name: name, inputJSON: input))
            }
        }
        let message = ChatMessage(role: .assistant, blocks: chatBlocks)
        messages.append(message)
        return message
    }

    private func makeSystemPrompt() -> String {
        let projectPath = appModel.workspace?.rootURL.path ?? "(no project loaded)"
        let currentFile = appModel.editorFileURL?.path ?? "(no open editor file)"
        var prompt = """
        You are TEXnologia's in-editor AI assistant for LaTeX authors.
        The user is working on a project located at: \(projectPath)
        The currently focused editor file is: \(currentFile)
        You can read, list, and write files within the project using the provided tools.

        DEFAULT EDIT SCOPE: Unless the user explicitly names another file or asks for a cross-file change, all edits MUST target the currently focused editor file via apply-to-open-editor. Do not write, rename, or delete other files in the project by default. If the user's request is ambiguous, ask before touching a different file.

        Prefer concise responses. Never write files outside the project root.
        When producing LaTeX edits, output valid LaTeX.
        """
        if let projectInstructions = loadProjectInstructions() {
            prompt += "\n\nPROJECT INSTRUCTIONS (from TEXNOLOGIA.md, overrides defaults where they conflict):\n\(projectInstructions)"
        }
        return prompt
    }

    private func loadProjectInstructions() -> String? {
        guard let root = appModel.workspace?.rootURL else { return nil }
        let candidates = [
            root.appendingPathComponent("TEXNOLOGIA.md"),
            root.appendingPathComponent(".texnologia").appendingPathComponent("agent.md")
        ]
        for url in candidates {
            if let data = try? String(contentsOf: url, encoding: .utf8) {
                let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
