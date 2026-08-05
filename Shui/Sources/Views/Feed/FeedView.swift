import SwiftUI

/// The Learn tab (mixed mode) or a topic's own feed (topic mode, pushed from
/// a topic page in Phase 3) — same view, different `FeedViewModel.Mode`.
struct FeedView: View {
    @StateObject private var viewModel: FeedViewModel
    @StateObject private var networkMonitor = NetworkMonitor()
    @Environment(\.dismiss) private var dismiss
    @State private var scrollPositionID: String?
    @State private var showSignInSheet = false
    var onExploreRequested: (() -> Void)?

    init(mode: FeedViewModel.Mode, environment: AppEnvironment, onExploreRequested: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: FeedViewModel(mode: mode, environment: environment))
        self.onExploreRequested = onExploreRequested
    }

    var body: some View {
        // Two nested readers on purpose. `outerGeo` sits *above* the
        // `.ignoresSafeArea()` below, so it still sees the real, tab-bar-
        // inclusive bottom safe area inset — `.ignoresSafeArea()` zeroes
        // that reporting for everything inside it, which is exactly why a
        // previous fix here (scoping the ignore to `.top` only, to keep the
        // quiz card's buttons clear of the tab bar) broke paging instead:
        // it shrank every page's own frame below one true screen height,
        // so the *next* page's top edge became visible at the bottom of
        // the current one. Pages need full screen height for paging to
        // line up with the physical screen; the tab bar clearance problem
        // belongs to the quiz card's own bottom padding, not the page
        // frame — see `tabBarBottomInset` threaded down to
        // `QuizOverlayContainer` below.
        GeometryReader { outerGeo in
            GeometryReader { geo in
                content(in: geo, tabBarBottomInset: outerGeo.safeAreaInsets.bottom)
            }
            .ignoresSafeArea()
        }
        .background(Color.black)
        // Harmless when this is a tab root (no nav bar there to begin
        // with); when pushed from a topic page in topic mode, this is what
        // stops the system back button from doubling up with
        // FeedPageView's own immersive one.
        .toolbar(.hidden, for: .navigationBar)
        // Full immersion while a video is actually playing; the tab bar
        // comes right back the moment it's paused, ends, or a quiz opens —
        // not tied to a swipe gesture, since up/down are already spoken for
        // by page-to-page paging and a tap already toggles play/pause.
        // Binding hide/reveal to a state transition that already exists
        // (rather than a new gesture competing with those two) is what
        // avoids a real conflict, not just a smaller one.
        .toolbar(isCurrentVideoPlaying ? .hidden : .automatic, for: .tabBar)
        .animation(.easeInOut(duration: 0.25), value: isCurrentVideoPlaying)
        .task { await viewModel.loadInitial() }
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            if isConnected {
                viewModel.flushPendingQuizAttempts()
            }
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInSheet()
        }
    }

    private var isCurrentVideoPlaying: Bool {
        if case .playing = viewModel.playerPool.states[viewModel.currentIndex] { return true }
        return false
    }

    @ViewBuilder
    private func content(in geo: GeometryProxy, tabBarBottomInset: CGFloat) -> some View {
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
                            onRequireSignIn: { showSignInSheet = true },
                            onBack: dismiss.callAsFunction,
                            tabBarBottomInset: tabBarBottomInset
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
