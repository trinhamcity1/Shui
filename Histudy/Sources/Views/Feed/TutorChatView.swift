import SwiftUI

/// Pro-tier "Ask AI Tutor" chat, scoped to one lesson. History persists in
/// SwiftData per lesson (the local mirror of the spec's Pro User Questions
/// table) and is fed back to the tutor service so answers can build on
/// earlier questions. The reply source is `TutorAIService`: offline
/// retrieval-based by default, backend LLM when `TutorBackendURL` is set.
struct TutorChatView: View {
    let lesson: LessonScript

    @EnvironmentObject private var appState: AppState
    @State private var messages: [TutorChatMessage] = []
    @State private var draft = ""
    @State private var isThinking = false

    private var language: AppLanguage { appState.profile.uiLanguage }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        openerBubble
                        ForEach(messages, id: \.id) { message in
                            messageBubble(message)
                        }
                        if isThinking {
                            HStack {
                                TutorLogoView(isSpeaking: true, emotion: .thinking, size: 32)
                                Spacer()
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .background(Theme.shell.canvas)
            .navigationTitle(L10n.chatTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { composer }
            .onAppear { messages = PersistenceController.shared.chatMessages(for: lesson.id) }
        }
    }

    private var openerBubble: some View {
        HStack(alignment: .top) {
            TutorLogoView(emotion: .happy, size: 32)
            Text(L10n.chatOpener.localized)
                .font(.subheadline)
                .foregroundStyle(Theme.shell.ink)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer()
        }
    }

    private func messageBubble(_ message: TutorChatMessage) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.isUser ? Color.white : Theme.shell.ink)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.isUser ? Theme.shell.gradientEnd : Color.white)
                )
            if !message.isUser { Spacer(minLength: 40) }
        }
        .id(message.id)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(L10n.chatPlaceholder.localized, text: $draft)
                .textFieldStyle(.roundedBorder)
                .disabled(isThinking)
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .tint(Theme.shell.gradientStart)
            .disabled(isThinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(.thinMaterial)
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        draft = ""

        PersistenceController.shared.addChatMessage(lessonID: lesson.id, isUser: true, text: question)
        messages = PersistenceController.shared.chatMessages(for: lesson.id)
        isThinking = true

        let priorUserQuestions = messages.filter(\.isUser).map(\.text)
        Task {
            let reply = await appState.tutorAI.chatReply(
                question: question,
                lesson: lesson,
                history: priorUserQuestions,
                profile: appState.profile
            )
            PersistenceController.shared.addChatMessage(
                lessonID: lesson.id,
                isUser: false,
                text: reply.text(for: language)
            )
            messages = PersistenceController.shared.chatMessages(for: lesson.id)
            isThinking = false
        }
    }
}
