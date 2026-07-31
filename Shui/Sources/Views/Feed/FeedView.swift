import SwiftUI

/// The Learn tab (mixed mode) or a topic's own feed (topic mode, pushed from
/// a topic page in Phase 3) — same view, different `FeedViewModel.Mode`.
struct FeedView: View {
    @StateObject private var viewModel: FeedViewModel
    @StateObject private var networkMonitor = NetworkMonitor()
    @State private var scrollPositionID: String?
    @State private var showSignInSheet = false
    var onExploreRequested: (() -> Void)?

    init(mode: FeedViewModel.Mode, environment: AppEnvironment, onExploreRequested: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: FeedViewModel(mode: mode, environment: environment))
        self.onExploreRequested = onExploreRequested
    }

    var body: some View {
        GeometryReader { geo in
            content(in: geo)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .task { await viewModel.loadInitial() }
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            if isConnected {
                viewModel.flushPendingQuizAttempts()
            }
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInStubSheet()
        }
    }

    @ViewBuilder
    private func content(in geo: GeometryProxy) -> some View {
        if viewModel.isInitialLoading {
            ProgressView().tint(.white)
        } else if let loadError = viewModel.loadError, viewModel.pages.isEmpty {
            ScrollView {
                FeedErrorStateView(message: loadError, onRetry: { Task { await viewModel.refresh() } })
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .refreshable { await viewModel.refresh() }
        } else if viewModel.pages.isEmpty {
            ScrollView {
                FeedEmptyStateView(dueReviewCount: 0, onExplore: { onExploreRequested?() })
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .refreshable { await viewModel.refresh() }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.pages.enumerated()), id: \.element.id) { index, page in
                        FeedPageView(
                            viewModel: viewModel,
                            page: page,
                            index: index,
                            onNextLesson: { scrollToNext(after: index) },
                            onRequireSignIn: { showSignInSheet = true }
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .id(page.id)
                        .onAppear { viewModel.onPageAppear(index: index) }
                        .onDisappear { viewModel.onPageDisappear(index: index) }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .tint(.white)
                            .frame(width: geo.size.width, height: 80)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollPositionID)
            .refreshable { await viewModel.refresh() }
        }
    }

    private func scrollToNext(after index: Int) {
        guard viewModel.pages.indices.contains(index + 1) else { return }
        withAnimation {
            scrollPositionID = viewModel.pages[index + 1].id
        }
    }
}
