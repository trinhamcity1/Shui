import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var greeting: TutorMessage?
    @Published private(set) var plannedItemCount: Int = 0
    @Published private(set) var estimatedMinutes: Int = 0

    private let tutorAI: TutorAIService

    init(tutorAI: TutorAIService = TutorAIServiceFactory.make()) {
        self.tutorAI = tutorAI
    }

    func load(profile: UserProfile) async {
        greeting = await tutorAI.greeting(profile: profile)

        let allProgress = PersistenceController.shared.allProgress()
        let items = SessionPlanner.buildSession(
            allQuestions: ContentStore.shared.questions,
            allProgress: allProgress,
            targetMinutes: profile.dailyGoalMinutes
        )
        plannedItemCount = items.count
        let totalSeconds = items.reduce(0.0) { $0 + $1.estimatedSeconds }
        estimatedMinutes = items.isEmpty ? 0 : max(1, Int((totalSeconds / 60).rounded()))
    }

    func buildSession(profile: UserProfile) -> [SessionItem] {
        SessionPlanner.buildSession(
            allQuestions: ContentStore.shared.questions,
            allProgress: PersistenceController.shared.allProgress(),
            targetMinutes: profile.dailyGoalMinutes
        )
    }
}
