import Combine
import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var selectedLanguage: AppLanguage = .vietnamese
    @Published var displayName: String = ""
    @Published var stateName: String = ""
    @Published var senator1: String = ""
    @Published var senator2: String = ""
    @Published var representative: String = ""
    @Published var governor: String = ""
    @Published var dailyGoalMinutes: Int = 7

    let availableStates = StateCapitalLookup.shared.allStateNames

    func complete(profile: UserProfile) {
        profile.uiLanguage = selectedLanguage
        profile.displayName = displayName
        profile.dailyGoalMinutes = dailyGoalMinutes

        var officials = LocalOfficialsProfile()
        officials.stateName = stateName.isEmpty ? nil : stateName
        officials.senator1 = senator1.isEmpty ? nil : senator1
        officials.senator2 = senator2.isEmpty ? nil : senator2
        officials.representative = representative.isEmpty ? nil : representative
        officials.governor = governor.isEmpty ? nil : governor
        profile.localOfficials = officials

        profile.hasCompletedOnboarding = true
        LocalizationManager.shared.setLanguage(selectedLanguage)
        PersistenceController.shared.save()
    }
}
