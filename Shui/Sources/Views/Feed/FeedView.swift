import SwiftUI

/// The Learn tab (mixed mode) or a topic's own feed (topic mode, pushed from
/// a topic page in Phase 3) — same view, different `FeedViewModel.Mode`.
struct FeedView: View {
    @StateObject private var viewModel: FeedViewModel
    @StateObject private var networkMonitor = NetworkMonitor()
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var scrollPositionID: String?
    @State private var showSignInSheet = false
    var onExploreRequested: (() -> Void)?
    /// Which ring tab this feed conceptually belongs to — Learn for its
    /// own mixed feed, Explore for a pushed topic, Profile for a pushed
    /// Saved/Liked/due-for-review list. Two things read this: which swipe
    /// modifier a root feed gets vs. a pushed one (see `body`), and —
    /// since `RootTabView`'s pager keeps every ring tab's content alive
    /// simultaneously, the same way `TabView` always did, rather than
    /// tearing it down when it scrolls off-screen — whether *this*
    /// instance is the one currently allowed to drive the shared tab bar
    /// (see the `appState.isTabBarHidden` handling below).
    private let owningRootTab: RootTab
    private var isTabRoot: Bool { owningRootTab == .learn }

    init(mode: FeedViewModel.Mode, environment: AppEnvironment, onExploreRequested: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: FeedViewModel(mode: mode, environment: environment))
        self.onExploreRequested = onExploreRequested
        switch mode {
        case .mixed: owningRootTab = .learn
        case .topic: owningRootTab = .explore
        case .videoList: owningRootTab = .profile
        }
    }

    var body: some View {
        // The root case gets the ring-level peek swipe (this is one of the
        // three tabs `RootTabView`'s pager lays out side by side); a
        // pushed instance gets pop-or-advance instead — see
        // `RingSwipeNavigation`'s own doc comment for why these are two
        // different modifiers rather than one with a flag.
        Group {
            if isTabRoot {
                feedContent.rootRingPeekSwipe()
            } else {
                feedContent.ringSwipeNavigation(onSwipeBack: dismiss.callAsFunction)
            }
        }
    }

    private var feedContent: some View {
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
        // comes right back the moment it's paused, ends, or a quiz opens.
        // `appState.isTabBarHidden` is a plain, directly-set boolean —
        // `RootTabView`'s own custom bottom bar reads it directly, with no
        // `.toolbar(for: .tabBar)`/`UITabBarController` bridging involved
        // to get out of sync the way it did three separate times before
        // this feed's tab bar was rebuilt as a custom view.
        //
        // Gated on `appState.rootTab == owningRootTab` throughout: since
        // the pager never tears this view down when its ring tab scrolls
        // off-screen, a video left playing in the background could
        // otherwise keep writing `true` forever, leaving the bar stuck
        // hidden on whichever tab the learner actually swiped to.
        .onAppear {
            if appState.rootTab == owningRootTab { appState.isTabBarHidden = isImmersed }
        }
        .onDisappear {
            if appState.rootTab == owningRootTab { appState.isTabBarHidden = false }
        }
        .onChange(of: isImmersed) { _, newValue in
            guard appState.rootTab == owningRootTab else { return }
            appState.isTabBarHidden = newValue
        }
        .onChange(of: appState.rootTab) { oldTab, newTab in
            if oldTab == owningRootTab, newTab != owningRootTab {
                // Just stopped being the active ring tab — let go of the
                // bar if we were the one holding it hidden. A no-op if we
                // weren't.
                appState.isTabBarHidden = false
            } else if newTab == owningRootTab {
                // Just became the active tab (or already were) — reflect
                // our own current immersion state, in case it changed
                // while we were the one off-screen.
                appState.isTabBarHidden = isImmersed
            }
        }
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

    /// Hidden once a video is loading or playing, not only once it's
    /// confirmed `.playing` — `.loading` is set synchronously the instant
    /// `prepare()` runs, before any async player-readiness callback, so
    /// gating on it too means the very first autoplay on landing in the
    /// feed hides the bar immediately rather than only on some later,
    /// unrelated state change.
    private var isImmersed: Bool {
        switch viewModel.playerPool.states[viewModel.currentIndex] {
        case .playing, .loading: return true
        default: return false
        }
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
