import Foundation

struct LLMToolDef {
    let name: String
    let description: String
    let inputSchema: [String: Any]
}

struct LLMResponse {
    enum Block {
        case text(String)
        case toolCall(id: String, name: String, inputJSON: String)
    }
    let blocks: [Block]
    let stopReason: String?
}

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidResponse(String)
    case httpError(Int, String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API 키가 설정되지 않았습니다. 설정에서 키를 입력하세요."
        case .invalidResponse(let s): return "응답을 해석할 수 없습니다: \(s)"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .network(let e): return "네트워크 오류: \(e.localizedDescription)"
        }
    }
}

protocol LLMClient {
    func send(
        messages: [ChatMessage],
        tools: [LLMToolDef],
        system: String?
    ) async throws -> LLMResponse
}

enum LLMClientFactory {
    static func make(for config: LLMConfiguration) throws -> LLMClient {
        guard config.isConfigured else { throw LLMError.missingAPIKey }
        switch config.provider {
        case .anthropic:
            return AnthropicClient(apiKey: config.apiKey, model: config.model, maxTokens: config.maxTokens)
        case .openai:
            return OpenAIClient(apiKey: config.apiKey, model: config.model, maxTokens: config.maxTokens)
        }
    }
}

// MARK: - Anthropic

final class AnthropicClient: LLMClient {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String, model: String, maxTokens: Int) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }

    func send(messages: [ChatMessage], tools: [LLMToolDef], system: String?) async throws -> LLMResponse {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": encode(messages: messages)
        ]
        if let system { body["system"] = system }
        if !tools.isEmpty {
            body["tools"] = tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.inputSchema
                ] as [String: Any]
            }
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("no http response")
        }
        if http.statusCode >= 400 {
            throw LLMError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let contentArray = root["content"] as? [[String: Any]]
        else {
            throw LLMError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }

        var blocks: [LLMResponse.Block] = []
        for block in contentArray {
            guard let type = block["type"] as? String else { continue }
            switch type {
            case "text":
                if let text = block["text"] as? String { blocks.append(.text(text)) }
            case "tool_use":
                if let id = block["id"] as? String,
                   let name = block["name"] as? String {
                    let inputObj = block["input"] ?? [:]
                    let inputData = (try? JSONSerialization.data(withJSONObject: inputObj, options: [.sortedKeys])) ?? Data()
                    blocks.append(.toolCall(
                        id: id,
                        name: name,
                        inputJSON: String(data: inputData, encoding: .utf8) ?? "{}"
                    ))
                }
            default:
                continue
            }
        }
        let stopReason = root["stop_reason"] as? String
        return LLMResponse(blocks: blocks, stopReason: stopReason)
    }

    private func encode(messages: [ChatMessage]) -> [[String: Any]] {
        messages.compactMap { msg in
            guard msg.role != .system else { return nil }
            let content: [[String: Any]] = msg.blocks.compactMap { block in
                switch block {
                case .text(let t):
                    return ["type": "text", "text": t]
                case .toolCall(let call):
                    let input = (try? JSONSerialization.jsonObject(with: Data(call.inputJSON.utf8))) ?? [:]
                    return [
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": input
                    ]
                case .toolResult(let result):
                    return [
                        "type": "tool_result",
                        "tool_use_id": result.toolUseID,
                        "content": result.content,
                        "is_error": result.isError
                    ]
                }
            }
            return [
                "role": msg.role.rawValue,
                "content": content
            ]
        }
    }
}

// MARK: - OpenAI

final class OpenAIClient: LLMClient {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String, model: String, maxTokens: Int) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }

    func send(messages: [ChatMessage], tools: [LLMToolDef], system: String?) async throws -> LLMResponse {
        var openMessages: [[String: Any]] = []
        if let system { openMessages.append(["role": "system", "content": system]) }

        for msg in messages {
            switch msg.role {
            case .user:
                let toolResults = msg.blocks.compactMap { block -> ChatToolResult? in
                    if case .toolResult(let r) = block { return r } else { return nil }
                }
                if !toolResults.isEmpty {
                    for result in toolResults {
                        openMessages.append([
                            "role": "tool",
                            "tool_call_id": result.toolUseID,
                            "content": result.content
                        ])
                    }
                } else {
                    openMessages.append([
                        "role": "user",
                        "content": msg.textContent
                    ])
                }
            case .assistant:
                var dict: [String: Any] = ["role": "assistant"]
                dict["content"] = msg.textContent.isEmpty ? NSNull() : msg.textContent
                let calls = msg.blocks.compactMap { block -> [String: Any]? in
                    guard case .toolCall(let call) = block else { return nil }
                    return [
                        "id": call.id,
                        "type": "function",
                        "function": ["name": call.name, "arguments": call.inputJSON]
                    ]
                }
                if !calls.isEmpty {
                    dict["tool_calls"] = calls
                }
                openMessages.append(dict)
            case .system:
                continue
            }
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": openMessages
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.inputSchema
                    ]
                ] as [String: Any]
            }
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("no http response")
        }
        if http.statusCode >= 400 {
            throw LLMError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let choice = choices.first,
            let message = choice["message"] as? [String: Any]
        else {
            throw LLMError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }

        var blocks: [LLMResponse.Block] = []
        if let text = message["content"] as? String, !text.isEmpty {
            blocks.append(.text(text))
        }
        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for call in toolCalls {
                let id = call["id"] as? String ?? UUID().uuidString
                let function = call["function"] as? [String: Any] ?? [:]
                let name = function["name"] as? String ?? ""
                let args = function["arguments"] as? String ?? "{}"
                blocks.append(.toolCall(id: id, name: name, inputJSON: args))
            }
        }

        let stopReason = choice["finish_reason"] as? String
        return LLMResponse(blocks: blocks, stopReason: stopReason)
    }
}
