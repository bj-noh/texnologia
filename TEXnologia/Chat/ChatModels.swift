import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatToolCall: Identifiable, Equatable, Codable {
    var id: String
    var name: String
    var inputJSON: String
}

struct ChatToolResult: Identifiable, Equatable, Codable {
    var id: String { toolUseID }
    var toolUseID: String
    var content: String
    var isError: Bool
}

enum ChatBlock: Equatable, Codable {
    case text(String)
    case toolCall(ChatToolCall)
    case toolResult(ChatToolResult)
}

struct ChatMessage: Identifiable, Equatable, Codable {
    var id = UUID()
    var role: ChatRole
    var blocks: [ChatBlock]
    var createdAt: Date = Date()

    var textContent: String {
        blocks.compactMap { block -> String? in
            if case .text(let text) = block { return text }
            return nil
        }.joined(separator: "\n")
    }

    var toolCalls: [ChatToolCall] {
        blocks.compactMap { block -> ChatToolCall? in
            if case .toolCall(let call) = block { return call }
            return nil
        }
    }
}

enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case openai

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openai: return "OpenAI"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-4-7"
        case .openai: return "gpt-4o"
        }
    }
}

struct LLMConfiguration: Equatable, Codable {
    var provider: LLMProvider
    var model: String
    var apiKey: String
    var maxTokens: Int

    static let `default` = LLMConfiguration(
        provider: .anthropic,
        model: LLMProvider.anthropic.defaultModel,
        apiKey: "",
        maxTokens: 4096
    )

    var isConfigured: Bool { !apiKey.isEmpty }
}
