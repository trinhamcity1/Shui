import Combine
import Foundation
import SwiftUI

/// Shared, app-wide state injected as a SwiftUI environment object.
///
/// Deliberately thin. Phase 1 introduces `AppEnvironment` holding the
/// repository layer, injected at the root so previews and tests can swap in
/// fakes; this holds only what genuinely must be process-wide before then.
@MainActor
final class AppState: ObservableObject {
    /// Device-local preferences (onboarding state, chosen interests).
    @Published var profile: UserProfile
    /// Set from `.onOpenURL`; drives a full-screen cover at the root so a
    /// deep link lands on the right screen regardless of which tab or
    /// navigation state the app happened to be in.
    @Published var pendingDeepLink: DeepLink?
    /// The selected root tab — lives here rather than as local `@State` on
    /// `RootTabView` so screens pushed several levels deep (a topic, a
    /// video feed) can also drive it directly for swipe-to-switch-tabs,
    /// without needing it threaded through every intermediate initializer.
    @Published var rootTab: RootTab = .learn
    /// Set directly by whichever `FeedView` is currently on screen (root or
    /// pushed) while a video is loading/playing — `RootTabView`'s own
    /// custom tab bar reads this to hide itself. Deliberately a plain,
    /// synchronous boolean rather than routed through SwiftUI's
    /// `.toolbar(for: .tabBar)` bridging to a real `UITabBarController`,
    /// which has needed three separate timing-sensitive fixes this session
    /// (all specific to the moment right after a cold launch) — this has
    /// no such bridging to get out of sync with in the first place.
    @Published var isTabBarHidden = false
    /// Live horizontal drag offset while a ring-level swipe (Learn <->
    /// Explore <-> Profile, from one of their own root screens) is in
    /// progress. `RootTabView`'s pager applies this to all three tabs'
    /// shared layout, so the tab being swiped toward is visibly revealed
    /// at the edge as the finger moves — not just decided and jumped to
    /// once the gesture ends. Written only by `RootRingPeekSwipe`; always
    /// 0 outside an active drag.
    @Published var rootDragOffset: CGFloat = 0

    init() {
        profile = PersistenceController.shared.fetchOrCreateProfile()
    }
}

enum RootTab: Hashable {
    case learn, explore, profile, debug

    /// Learn, Explore, and Profile only — the swipe-navigation ring (and
    /// `RootTabView`'s pager, which lays these three out side by side)
    /// never includes the debug tab, which stays reachable by tapping its
    /// own tab bar icon like it always has, and replaces the whole screen
    /// rather than taking a slot in the ring.
    static let ring: [RootTab] = [.learn, .explore, .profile]

    /// `nil` at the last tab in the ring — swiping forward past Profile
    /// (or backward past Learn, via `previousInRing`) simply does nothing,
    /// rather than wrapping around.
    var nextInRing: RootTab? {
        guard let index = Self.ring.firstIndex(of: self), index + 1 < Self.ring.count else { return nil }
        return Self.ring[index + 1]
    }

    var previousInRing: RootTab? {
        guard let index = Self.ring.firstIndex(of: self), index > 0 else { return nil }
        return Self.ring[index - 1]
    }
}
