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
    @Published var rootTab: RootTab = .social

    init() {
        profile = PersistenceController.shared.fetchOrCreateProfile()
    }
}

enum RootTab: Hashable {
    // "social", not "learn" — phase-07 §6 replaces the old composed
    // review/interest video feed as the primary scrolling tab with the
    // Social feed of on-demand lessons. `FeedComposer` and its `.mixed`
    // `FeedViewModel.Mode` are untouched and still fully tested
    // (FeedComposerTests) but are no longer wired to any tab as of this
    // change — where curated/spaced-repetition review surfaces next is an
    // open product question, not resolved by this rename.
    case social, explore, profile, debug

    /// Social, Explore, and Profile only — the swipe-navigation ring never
    /// includes the debug tab, which stays reachable by tapping its own
    /// tab bar icon like it always has.
    private static let ring: [RootTab] = [.social, .explore, .profile]

    /// `nil` at the last tab in the ring — swiping forward past Profile
    /// (or backward past Social, via `previousInRing`) simply does nothing,
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
