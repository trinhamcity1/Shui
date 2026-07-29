import SwiftUI

/// The primary interface: a TikTok-style, full-screen vertical paging feed
/// of lessons. Swipe up for the next lesson, down for the previous one.
/// Each page plays its whiteboard lesson, then presents a short quiz before
/// nudging the learner to keep scrolling. Feed order and resurfacing come
/// from `FeedPlanner` via `FeedViewModel`.
struct FeedView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = FeedViewModel()

    private var language: AppLanguage { appState.profile.uiLanguage }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.entries) { entry in
                    if let lesson = viewModel.lesson(for: entry) {
                        FeedLessonPageView(
                            entry: entry,
                            lesson: lesson,
                            isActive: viewModel.currentEntryID == entry.id,
                            feedVM: viewModel,
                            narrator: appState.narrator
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $viewModel.currentEntryID)
        .background(Theme.scene.canvas.ignoresSafeArea())
        .onAppear {
            if viewModel.entries.isEmpty {
                viewModel.load()
            }
        }
        .sheet(isPresented: $viewModel.showSignInPrompt) {
            SignInPromptView()
        }
    }
}
