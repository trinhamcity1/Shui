import SwiftUI

/// A short, four-step first-run flow: pick a language, tell the character
/// your name, add your state (and optionally local officials), and set a
/// daily goal. Everything here writes into the single local `UserProfile`.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var step = 0

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $step) {
                welcomeStep.tag(0)
                nameStep.tag(1)
                stateStep.tag(2)
                goalStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack {
                if step > 0 {
                    Button(L10n.back.localized) { step -= 1 }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.shell.gradientEnd)
                }
                Spacer()
                if step < totalSteps - 1 {
                    Button(L10n.next.localized) { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.shell.gradientStart)
                } else {
                    Button(L10n.onboardingGetStarted.localized) {
                        viewModel.complete(profile: appState.profile)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.shell.gradientStart)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .shuiShellBackground()
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            TutorLogoView(emotion: .happy, size: 88)
            Text(L10n.onboardingWelcomeTitle.localized)
                .font(.title.bold())
                .foregroundStyle(Theme.shell.ink)
            Text(L10n.onboardingWelcomeBody.localized)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.shell.metadata)

            Picker(L10n.onboardingChooseLanguageTitle.localized, selection: $viewModel.selectedLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
    }

    private var nameStep: some View {
        VStack(spacing: 20) {
            Text(L10n.onboardingNameTitle.localized).font(.title2.bold()).foregroundStyle(Theme.shell.ink)
            TextField(L10n.onboardingNamePlaceholder.localized, text: $viewModel.displayName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
        }
        .padding()
    }

    private var stateStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.onboardingStateTitle.localized).font(.title2.bold()).foregroundStyle(Theme.shell.ink)
                Text(L10n.onboardingStateBody.localized).font(.subheadline).foregroundStyle(Theme.shell.metadata)

                Picker(L10n.onboardingStateTitle.localized, selection: $viewModel.stateName) {
                    Text("—").tag("")
                    ForEach(viewModel.availableStates, id: \.self) { state in
                        Text(state).tag(state)
                    }
                }
                .pickerStyle(.menu)

                Text(L10n.onboardingLocalOfficialsTitle.localized).font(.headline).foregroundStyle(Theme.shell.ink).padding(.top)
                Text(L10n.onboardingLocalOfficialsBody.localized).font(.caption).foregroundStyle(Theme.shell.metadata)

                TextField(L10n.onboardingSenator1.localized, text: $viewModel.senator1).textFieldStyle(.roundedBorder)
                TextField(L10n.onboardingSenator2.localized, text: $viewModel.senator2).textFieldStyle(.roundedBorder)
                TextField(L10n.onboardingRepresentative.localized, text: $viewModel.representative).textFieldStyle(.roundedBorder)
                TextField(L10n.onboardingGovernor.localized, text: $viewModel.governor).textFieldStyle(.roundedBorder)
            }
            .padding()
        }
    }

    private var goalStep: some View {
        VStack(spacing: 20) {
            Text(L10n.onboardingGoalTitle.localized).font(.title2.bold()).foregroundStyle(Theme.shell.ink)
            Text(L10n.onboardingGoalBody.localized).font(.subheadline).foregroundStyle(Theme.shell.metadata)
            Stepper("\(viewModel.dailyGoalMinutes) min", value: $viewModel.dailyGoalMinutes, in: 3...20)
                .padding(.horizontal)
        }
        .padding()
    }
}
