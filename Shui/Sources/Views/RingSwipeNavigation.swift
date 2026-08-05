import SwiftUI

/// Drives the app's swipe-to-navigate model: Learn, Explore, and Profile
/// form a fixed ring, and any screen pushed on top of Explore or Profile
/// (a category, a topic, a video feed) sits on that tab's own stack without
/// affecting the ring itself.
///
/// Two rules, applied uniformly everywhere this is attached:
/// - **Forward** (right-to-left) always advances one step through the ring,
///   no matter how deep the current tab is pushed — it never pops anything.
/// - **Backward** (left-to-right) pops one level of the current push stack
///   if there is one (`isRoot == false`); only once a tab is back at its
///   own root does backward retreat one step through the ring.
///
/// Both stop dead at the ends (Learn going back, Profile going forward) —
/// dragging in a direction with nowhere to go simply doesn't move the
/// content at all, rather than a rubber-band tug that implies something
/// would happen on release.
///
/// The content tracks the finger 1:1 while dragging (an instagram-style
/// "this is a physical sheet of paper" feel, not a discrete gesture that
/// only *decides* where to go once released): dragging past the commit
/// threshold and lifting finishes the slide the rest of the way off-screen
/// before the real navigation change lands underneath it; releasing short
/// of the threshold springs back to rest. `onSwipeBack` lets a caller pass
/// its own already-captured `dismiss` instead of this modifier's own
/// `@Environment(\.dismiss)` — needed for anything instantiated inside a
/// `ForEach`/`LazyVStack`, where `@Environment` re-resolution is unreliable
/// (see `FeedView`'s own comment on the same gotcha).
struct RingSwipeNavigation: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let isRoot: Bool
    var onSwipeBack: (() -> Void)?

    @State private var offset: CGFloat = 0
    /// Blocks a new drag from starting while the previous one is still
    /// mid-commit-animation — the underlying content is about to be
    /// swapped out from under it anyway.
    @State private var isCommitting = false

    /// How far, in points, a drag has to travel horizontally before
    /// release commits the navigation instead of springing back. A
    /// starting point, not a tuned value — this sandbox has no device to
    /// tune it against.
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
                        // No animation wrapper here on purpose — this needs
                        // to read as glued to the touch, not catching up to
                        // it a frame later the way an animated value would.
                        offset = canCommit(dx: value.translation.width) ? value.translation.width : 0
                    }
                    .onEnded { value in
                        guard !isCommitting, isHorizontalDrag(value.translation) else { return }
                        handleEnded(dx: value.translation.width)
                    }
            )
    }

    /// Only a drag that's clearly more horizontal than vertical counts, so
    /// this never fights a feed's own vertical video-paging scroll (or any
    /// other vertical scroll view) for the same touch.
    private func isHorizontalDrag(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * 1.5
    }

    private func canCommit(dx: CGFloat) -> Bool {
        if dx < 0 {
            return appState.rootTab.nextInRing != nil
        }
        return isRoot ? appState.rootTab.previousInRing != nil : true
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
        if isRoot {
            guard let previous = appState.rootTab.previousInRing else { return }
            appState.rootTab = previous
        } else if let onSwipeBack {
            onSwipeBack()
        } else {
            dismiss()
        }
    }
}

extension View {
    /// - Parameters:
    ///   - isRoot: `true` for a tab's own root screen (nothing to pop);
    ///     `false` for anything pushed on top of one.
    ///   - onSwipeBack: Overrides this modifier's own `dismiss` for the
    ///     `isRoot == false` case — pass the caller's own captured
    ///     `dismiss` when attaching this somewhere `@Environment` isn't
    ///     reliably resolved (see the type's own doc comment).
    func ringSwipeNavigation(isRoot: Bool, onSwipeBack: (() -> Void)? = nil) -> some View {
        modifier(RingSwipeNavigation(isRoot: isRoot, onSwipeBack: onSwipeBack))
    }
}
