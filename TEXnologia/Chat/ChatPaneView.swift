import SwiftUI

struct ChatPaneView: View {
    @ObservedObject var session: ChatSession
    @Binding var isPresented: Bool
    @State private var draft: String = ""
    @State private var paneHeight: CGFloat = 400
    @State private var inputHeight: CGFloat = 42
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            FolioTheme.border.frame(height: 1)
            content
            inputBar
        }
        .foregroundStyle(FolioTheme.text)
        .tint(FolioTheme.accent)
        .background(FolioTheme.surface)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { paneHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newValue in paneHeight = newValue }
            }
        )
    }

    private var maxInputHeight: CGFloat {
        max(120, paneHeight * 0.5)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FolioTheme.accent)
                .frame(width: 30, height: 30)
                .background(FolioTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Assistant")
                    .font(.system(size: 12, weight: .semibold))
                Text(session.isStreaming ? "Working on your request" : "A little help for your next idea")
                    .font(.system(size: 10))
                    .foregroundStyle(FolioTheme.muted)
                    .lineLimit(1)
            }
            Spacer()

            if session.isStreaming {
                Button {
                    session.cancel()
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(FolioIconButtonStyle())
                .help("Stop generating")
            }

            Button {
                session.clear()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(FolioIconButtonStyle())
            .help("Clear conversation")
            .disabled(session.messages.isEmpty)

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(FolioIconButtonStyle())
            .help("Close AI pane")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(FolioTheme.accent)
                .frame(width: 60, height: 60)
                .background(FolioTheme.accentSoft, in: RoundedRectangle(cornerRadius: 16))
            Text("Make room for a little help.")
                .font(.system(size: 17, weight: .semibold))
            Text("Connect your AI provider to ask questions,\nrefine your writing, and edit project files.")
                .font(.system(size: 12))
                .foregroundStyle(FolioTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button("Set up AI Assistant") {
                openSettings()
            }
            .buttonStyle(FolioPrimaryButtonStyle())
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(FolioTheme.accent)
                .frame(width: 60, height: 60)
                .background(FolioTheme.accentSoft, in: RoundedRectangle(cornerRadius: 16))
            Text("What are you working on?")
                .font(.system(size: 17, weight: .semibold))
            Text("Ask a question, polish a paragraph,\nor get help with your LaTeX project.")
                .font(.system(size: 12))
                .foregroundStyle(FolioTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 18) {
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
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .onChange(of: session.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var inputBar: some View {
        let enabled = session.isConfigured && !session.isStreaming
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ChatInputTextView(
                    text: $draft,
                    measuredHeight: $inputHeight,
                    placeholder: "Ask about your project…",
                    font: .systemFont(ofSize: 13),
                    minHeight: 42,
                    maxHeight: maxInputHeight,
                    isEnabled: enabled,
                    onSubmit: sendIfReady
                )
                .frame(height: clampedInputHeight)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .opacity(enabled ? 1.0 : 0.55)

                Button {
                    sendIfReady()
                } label: {
                    Image(systemName: session.isStreaming ? "ellipsis" : "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 16, height: 20)
                }
                .buttonStyle(FolioPrimaryButtonStyle())
                .help("Send message (Return)")
                .disabled(draft.isEmpty || session.isStreaming || !session.isConfigured)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
            .background(FolioTheme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FolioTheme.border, lineWidth: 1))

            Text("Return to send · Shift + Return for a new line")
                .font(.system(size: 9))
                .foregroundStyle(FolioTheme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var clampedInputHeight: CGFloat {
        min(maxInputHeight, max(42, inputHeight))
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
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.role == .user ? "You" : "Assistant")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FolioTheme.muted)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(for: block)
                }
            }
            .padding(12)
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
                .foregroundStyle(FolioTheme.text)
                .lineSpacing(4)
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
        case .user: return FolioTheme.accentSoft
        case .assistant: return FolioTheme.canvas
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
                .foregroundStyle(FolioTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text(truncated(inputJSON))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(FolioTheme.muted)
                    .lineLimit(3)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FolioTheme.accentSoft)
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
                .foregroundStyle(isError ? Color.red : FolioTheme.muted)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
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
                .foregroundStyle(FolioTheme.muted)
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
