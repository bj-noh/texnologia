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
    case gemini
    case xai
    case deepseek
    case mistral
    case groq
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI (GPT / Codex)"
        case .gemini: return "Google (Gemini)"
        case .xai: return "xAI (Grok)"
        case .deepseek: return "DeepSeek"
        case .mistral: return "Mistral"
        case .groq: return "Groq"
        case .ollama: return "Ollama (Local)"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-4-7"
        case .openai: return "gpt-4o"
        case .gemini: return "gemini-2.0-flash"
        case .xai: return "grok-2-latest"
        case .deepseek: return "deepseek-chat"
        case .mistral: return "mistral-large-latest"
        case .groq: return "llama-3.3-70b-versatile"
        case .ollama: return "llama3.1"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .anthropic:
            return ["claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "o3-mini", "o1", "o1-mini", "codex-mini-latest"]
        case .gemini:
            return ["gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash"]
        case .xai:
            return ["grok-2-latest", "grok-2-1212", "grok-beta"]
        case .deepseek:
            return ["deepseek-chat", "deepseek-reasoner"]
        case .mistral:
            return ["mistral-large-latest", "mistral-medium-latest", "mistral-small-latest"]
        case .groq:
            return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"]
        case .ollama:
            return ["llama3.1", "llama3.2", "qwen2.5-coder", "mistral"]
        }
    }

    var endpoint: URL {
        switch self {
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        case .openai:    return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .gemini:    return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .xai:       return URL(string: "https://api.x.ai/v1/chat/completions")!
        case .deepseek:  return URL(string: "https://api.deepseek.com/v1/chat/completions")!
        case .mistral:   return URL(string: "https://api.mistral.ai/v1/chat/completions")!
        case .groq:      return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .ollama:    return URL(string: "http://localhost:11434/v1/chat/completions")!
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama: return false
        default: return true
        }
    }

    var apiKeyHint: String {
        switch self {
        case .anthropic:
            return "Anthropic 키는 sk-ant-로 시작합니다. 키는 로컬 설정에만 저장됩니다."
        case .openai:
            return "OpenAI 키는 sk-로 시작합니다. GPT, o-시리즈, Codex 모델 모두 같은 키를 사용합니다."
        case .gemini:
            return "Google AI Studio에서 발급한 Gemini API 키를 입력하세요 (aistudio.google.com/apikey)."
        case .xai:
            return "xAI 콘솔(console.x.ai)에서 발급한 키를 입력하세요. 접두사는 xai-입니다."
        case .deepseek:
            return "DeepSeek 플랫폼(platform.deepseek.com)에서 발급한 API 키를 입력하세요."
        case .mistral:
            return "Mistral 콘솔(console.mistral.ai)에서 발급한 API 키를 입력하세요."
        case .groq:
            return "Groq 콘솔(console.groq.com)에서 발급한 키를 입력하세요. 접두사는 gsk_입니다."
        case .ollama:
            return "로컬 Ollama 데몬을 사용합니다. 기본 엔드포인트는 http://localhost:11434 이며 API 키가 필요 없습니다."
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

    var isConfigured: Bool {
        if !provider.requiresAPIKey { return true }
        return !apiKey.isEmpty
    }
}
