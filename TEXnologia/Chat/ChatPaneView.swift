import SwiftUI

struct ChatPaneView: View {
    @ObservedObject var session: ChatSession
    @Binding var isPresented: Bool
    @State private var draft: String = ""
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            inputBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
            Text("AI Assistant")
                .font(.system(size: 12, weight: .semibold))
            Spacer()

            if session.isStreaming {
                Button {
                    session.cancel()
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .help("Stop generating")
            }

            Button {
                session.clear()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Clear conversation")
            .disabled(session.messages.isEmpty)

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close AI pane")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if !session.isConfigured {
            notConfiguredState
        } else if session.messages.isEmpty {
            welcomeState
        } else {
            messageList
        }
    }

    private var notConfiguredState: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.radiowaves.forward")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("API 키가 설정되지 않았습니다.")
                .font(.system(size: 12))
            Text("Preferences → AI 탭에서 키를 입력하세요.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Open Preferences") {
                openSettings()
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tint)
            Text("무엇을 도와드릴까요?")
                .font(.system(size: 12, weight: .medium))
            Text("프로젝트 파일을 읽고 수정할 수 있어요.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.messages) { message in
                        ChatMessageBubble(message: message)
                            .id(message.id)
                    }
                    if let status = session.statusMessage {
                        StatusRow(text: status)
                    }
                    if let error = session.lastError {
                        ErrorRow(text: error)
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .onChange(of: session.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("Ask about the project…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(.system(size: 12))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
                        )
                )
                .disabled(!session.isConfigured || session.isStreaming)
                .onSubmit(sendIfReady)

            Button {
                sendIfReady()
            } label: {
                Image(systemName: session.isStreaming ? "ellipsis.circle" : "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(session.isStreaming ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(draft.isEmpty || session.isStreaming || !session.isConfigured)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func sendIfReady() {
        let text = draft
        draft = ""
        session.send(userText: text)
    }
}

private struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            Text(message.role == .user ? "You" : "Assistant")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(for: block)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bubbleBackground)
            )
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    @ViewBuilder
    private func blockView(for block: ChatBlock) -> some View {
        switch block {
        case .text(let text):
            Text(text)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .toolCall(let call):
            ToolCallRow(name: call.name, inputJSON: call.inputJSON)
        case .toolResult(let result):
            ToolResultRow(content: result.content, isError: result.isError)
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: return Color.accentColor.opacity(0.14)
        case .assistant: return Color(nsColor: .controlBackgroundColor).opacity(0.6)
        case .system: return Color.clear
        }
    }
}

private struct ToolCallRow: View {
    let name: String
    let inputJSON: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "wrench.adjustable")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text(truncated(inputJSON))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }

    private func truncated(_ s: String) -> String {
        s.count > 240 ? String(s.prefix(240)) + "…" : s
    }
}

private struct ToolResultRow: View {
    let content: String
    let isError: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.seal")
                .font(.system(size: 10))
                .foregroundStyle(isError ? Color.red : Color.green)
            Text(truncated(content))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(isError ? Color.red : .secondary)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill((isError ? Color.red : Color.green).opacity(0.06))
        )
    }

    private func truncated(_ s: String) -> String {
        s.count > 600 ? String(s.prefix(600)) + "…" : s
    }
}

private struct StatusRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ErrorRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
