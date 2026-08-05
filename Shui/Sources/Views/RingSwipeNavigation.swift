import SwiftUI

/// Only a drag that's clearly more horizontal than vertical counts, so
/// neither swipe modifier below ever fights a feed's own vertical
/// video-paging scroll (or any other vertical scroll view) for the same
/// touch.
private func isHorizontalDrag(_ translation: CGSize) -> Bool {
    abs(translation.width) > abs(translation.height) * 1.5
}

/// Attached to a ring tab's own root content (`FeedView` in `.mixed` mode,
/// `ExploreView`, `ProfileView`) — never to anything pushed on top of one,
/// which uses `ringSwipeNavigation(onSwipeBack:)` below instead.
///
/// Tracks a live horizontal drag and writes it to `appState.rootDragOffset`
/// rather than moving its own content — `RootTabView`'s pager applies that
/// offset to all three ring tabs' shared layout, so the tab being swiped
/// toward (a real, already-live sibling view — Explore, Profile, and
/// Learn's own feed all stay instantiated simultaneously, the same way
/// they did under `TabView`) is visibly revealed at the edge as the finger
/// moves, the same way Instagram's own feed-to-camera swipe works. Forward
/// (right-to-left) always advances the ring; backward (left-to-right)
/// retreats it — there's nothing to pop from a tab's own root, so both
/// directions just move the ring here.
struct RootRingPeekSwipe: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @State private var isCommitting = false

    /// How far, in points, a drag has to travel before release commits the
    /// swap instead of springing back. A starting point, not a tuned
    /// value — this sandbox has no device to tune it against.
    private let commitThreshold: CGFloat = 90

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { value in
                    guard !isCommitting, isHorizontalDrag(value.translation) else { return }
                    let dx = value.translation.width
                    // No animation wrapper — this needs to read as glued
                    // to the touch, not catching up to it a frame later.
                    appState.rootDragOffset = canCommit(dx: dx) ? dx : 0
                }
                .onEnded { value in
                    guard !isCommitting, isHorizontalDrag(value.translation) else { return }
                    handleEnded(dx: value.translation.width)
                }
        )
    }

    private func canCommit(dx: CGFloat) -> Bool {
        dx < 0 ? appState.rootTab.nextInRing != nil : appState.rootTab.previousInRing != nil
    }

    private func handleEnded(dx: CGFloat) {
        guard abs(dx) > commitThreshold,
              let target = dx < 0 ? appState.rootTab.nextInRing : appState.rootTab.previousInRing
        else {
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.82)) {
                appState.rootDragOffset = 0
            }
            return
        }
        isCommitting = true
        // Animating `rootTab` and `rootDragOffset` back to 0 in the same
        // transaction is what makes this a continuation of the drag
        // rather than a snap-then-jump: the pager's own offset —
        // `-index * width + rootDragOffset` — interpolates smoothly from
        // wherever the finger left off straight to the new tab's resting
        // position, because both halves of that expression are animating
        // together.
        withAnimation(.easeOut(duration: 0.28), completionCriteria: .logicallyComplete) {
            appState.rootTab = target
            appState.rootDragOffset = 0
        } completion: {
            isCommitting = false
        }
    }
}

extension View {
    /// Only for a ring tab's own root content — see `RootRingPeekSwipe`'s
    /// doc comment.
    func rootRingPeekSwipe() -> some View {
        modifier(RootRingPeekSwipe())
    }
}

/// Attached to anything pushed on top of Explore or Profile's own stack —
/// a category, a topic, a video feed. Backward (left-to-right) pops one
/// level (`onSwipeBack`, or this modifier's own `dismiss` if the caller
/// doesn't need to pass its own — see the parameter doc below). Forward
/// (right-to-left) always advances the ring directly, the same rule as
/// `RootRingPeekSwipe`, bypassing however many levels are pushed — a
/// learner three screens deep in a topic can still swipe straight to
/// Profile in one motion.
///
/// Unlike the root-level swipe, this doesn't get a live peek of what's
/// underneath: the current screen tracks the finger and slides fully
/// off-screen once committed, but the screen it's revealing isn't drawn
/// alongside it. Building that properly would mean either giving up
/// `NavigationStack`'s own safe, working interactive-pop-gesture behavior
/// in favor of reimplementing it, or fighting a genuine gesture-priority
/// conflict between this and the ring-level peek swipe several levels up
/// the same view hierarchy — deferred rather than attempted blind with no
/// device to verify either path against.
struct RingSwipeNavigation: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var onSwipeBack: (() -> Void)?

    @State private var offset: CGFloat = 0
    @State private var isCommitting = false

    private let commitThreshold: CGFloat = 90
    /// How far content visibly finishes sliding once a swipe commits —
    /// comfortably past any real device width, so "fully off-screen"
    /// never depends on knowing the actual screen size.
    private let commitSlideDistance: CGFloat = 600

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { value in
                        guard !isCommitting, isHorizontalDrag(value.translation) else { return }
                        offset = canCommit(dx: value.translation.width) ? value.translation.width : 0
                    }
                    .onEnded { value in
                        guard !isCommitting, isHorizontalDrag(value.translation) else { return }
                        handleEnded(dx: value.translation.width)
                    }
            )
    }

    private func canCommit(dx: CGFloat) -> Bool {
        dx < 0 ? appState.rootTab.nextInRing != nil : true
    }

    private func handleEnded(dx: CGFloat) {
        guard abs(dx) > commitThreshold, canCommit(dx: dx) else {
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.82)) {
                offset = 0
            }
            return
        }
        let direction: CGFloat = dx < 0 ? -1 : 1
        let action = dx < 0 ? swipeForward : swipeBack
        isCommitting = true
        withAnimation(.easeIn(duration: 0.22), completionCriteria: .logicallyComplete) {
            offset = direction * commitSlideDistance
        } completion: {
            action()
            offset = 0
            isCommitting = false
        }
    }

    private func swipeForward() {
        guard let next = appState.rootTab.nextInRing else { return }
        appState.rootTab = next
    }

    private func swipeBack() {
        if let onSwipeBack {
            onSwipeBack()
        } else {
            dismiss()
        }
    }
}

extension View {
    /// - Parameter onSwipeBack: Overrides this modifier's own `dismiss` —
    ///   pass the caller's own already-captured `dismiss` when attaching
    ///   this somewhere `@Environment` isn't reliably resolved, such as a
    ///   view instantiated inside a `ForEach`/`LazyVStack` (see
    ///   `FeedView`'s own comment on that gotcha).
    func ringSwipeNavigation(onSwipeBack: (() -> Void)? = nil) -> some View {
        modifier(RingSwipeNavigation(onSwipeBack: onSwipeBack))
    }
}
