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
/// Both stop dead at the ends (Learn going back, Profile going forward)
/// rather than wrapping around. `onSwipeBack` lets a caller pass its own
/// already-captured `dismiss` instead of this modifier's own
/// `@Environment(\.dismiss)` — needed for anything instantiated inside a
/// `ForEach`/`LazyVStack`, where `@Environment` re-resolution is unreliable
/// (see `FeedView`'s own comment on the same gotcha).
struct RingSwipeNavigation: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let isRoot: Bool
    var onSwipeBack: (() -> Void)?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    // Direction-locked: only a drag that's clearly more
                    // horizontal than vertical counts, so this never fights
                    // a feed's own vertical video-paging scroll for the
                    // same touch. Thresholds are a starting point — this
                    // sandbox has no device to tune them against.
                    guard abs(dx) > abs(dy) * 1.5, abs(dx) > 60 else { return }
                    if dx < 0 {
                        swipeForward()
                    } else {
                        swipeBack()
                    }
                }
        )
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
