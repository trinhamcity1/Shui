import SwiftUI

/// Presented from the feed's `sparkles` rail button, over the paused video —
/// guests never reach this (gated at the rail button itself, same
/// convention as Like). Chat transcript with a Discuss/Quiz me segmented
/// toggle at top, suggested-reply chips above the composer, and streaming
/// text driven entirely by `AITutorViewModel`'s live Firestore listener —
/// this view never talks to the network directly.
struct AITutorSheet: View {
    let videoId: String
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AITutorViewModel
    @State private var draftText = ""
    @FocusState private var composerFocused: Bool

    init(videoId: String, environment: AppEnvironment) {
        self.videoId = videoId
        self.environment = environment
        _viewModel = StateObject(wrappedValue: AITutorViewModel(videoId: videoId, environment: environment))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modePicker
                Divider()
                transcript
                if !viewModel.suggestedReplies.isEmpty {
                    suggestedReplyRow
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(theme.error)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
                Divider()
                composer
            }
            .navigationTitle("AI Tutor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            AppAnalytics.logAIOpened(videoId: videoId)
            await viewModel.start()
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $viewModel.mode) {
            Text("Discuss").tag(AIThreadMode.discuss)
            Text("Quiz me").tag(AIThreadMode.quizMe)
        }
        .pickerStyle(.segmented)
        .padding(16)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        if index > 0, viewModel.messages[index - 1].mode != message.mode {
                            modeDivider(for: message.mode)
                        }
                        AIMessageBubble(message: message)
                            .id(message.id)
                    }
                    if viewModel.isSendingSessionStart, viewModel.messages.isEmpty {
                        HStack {
                            TypingDotsView()
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.surfaceSubtle))
                            Spacer(minLength: 40)
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                guard let lastId = viewModel.messages.last?.id else { return }
                withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
            }
        }
    }

    private func modeDivider(for mode: AIThreadMode) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(theme.borderSubtle).frame(height: 1)
            Text(mode == .discuss ? "Discuss" : "Quiz me")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.textTertiary)
                .fixedSize()
            Rectangle().fill(theme.borderSubtle).frame(height: 1)
        }
    }

    private var suggestedReplyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.suggestedReplies, id: \.self) { reply in
                    Button(reply) {
                        Task { await viewModel.send(reply) }
                    }
                    .buttonStyle(.shuiPillOutline)
                    .font(.caption)
                    .disabled(viewModel.isSending)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(
                viewModel.mode == .discuss ? "Ask about this video" : "Type your answer",
                text: $draftText,
                axis: .vertical
            )
            .lineLimit(1...4)
            .focused($composerFocused)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.surfaceSubtle))

            Button {
                let text = draftText
                draftText = ""
                Task { await viewModel.send(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(isComposerEmpty ? theme.textTertiary : theme.accent)
            }
            .disabled(isComposerEmpty || viewModel.isSending || viewModel.isSendingSessionStart)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var isComposerEmpty: Bool {
        draftText.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

private struct AIMessageBubble: View {
    @Environment(\.theme) private var theme
    let message: AIMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        if message.isStreaming && message.text.isEmpty {
            TypingDotsView()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.surfaceSubtle))
        } else {
            HStack(alignment: .bottom, spacing: 3) {
                Text(message.text)
                    .font(.subheadline)
                if message.isStreaming {
                    StreamingCursor()
                }
            }
            .foregroundStyle(message.role == .assistant ? theme.textPrimary : theme.textOnAccent)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(message.role == .assistant ? theme.surfaceSubtle : theme.accent)
            )
        }
    }
}

private struct StreamingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(.secondary)
            .frame(width: 2, height: 14)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

private struct TypingDotsView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animate ? 1 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}
