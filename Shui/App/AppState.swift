import Combine
import Foundation
import SwiftUI

/// Shared, app-wide services injected as a SwiftUI environment object.
/// Content and persistence are both process-wide singletons already
/// (`ContentStore`, `PersistenceController`), so this mostly wires together
/// the pieces that do need a single shared instance across the view tree:
/// the current profile, the speech narrator (owns an `AVSpeechSynthesizer`),
/// and the AI tutor service.
@MainActor
final class AppState: ObservableObject {
    @Published var profile: UserProfile
    let narrator = SpeechNarrator()
    let tutorAI: TutorAIService = TutorAIServiceFactory.make()

    init() {
        profile = PersistenceController.shared.fetchOrCreateProfile()
    }
}
