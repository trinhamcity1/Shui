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

    init() {
        profile = PersistenceController.shared.fetchOrCreateProfile()
    }
}
