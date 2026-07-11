import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var localOfficials = LocalOfficialsProfile()

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.settingsLanguage.localized) {
                    Picker(L10n.settingsLanguage.localized, selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.white)

                Section(L10n.settingsDailyGoal.localized) {
                    Stepper("\(appState.profile.dailyGoalMinutes) min", value: dailyGoalBinding, in: 3...20)
                        .foregroundStyle(Theme.shell.ink)
                }
                .listRowBackground(Color.white)

                Section(L10n.settingsLocalOfficials.localized) {
                    Picker(L10n.onboardingStateTitle.localized, selection: stateBinding) {
                        Text("—").tag("")
                        ForEach(StateCapitalLookup.shared.allStateNames, id: \.self) { state in
                            Text(state).tag(state)
                        }
                    }
                    TextField(L10n.onboardingSenator1.localized, text: fieldBinding(\.senator1))
                    TextField(L10n.onboardingSenator2.localized, text: fieldBinding(\.senator2))
                    TextField(L10n.onboardingRepresentative.localized, text: fieldBinding(\.representative))
                    TextField(L10n.onboardingGovernor.localized, text: fieldBinding(\.governor))
                }
                .listRowBackground(Color.white)

                Section(L10n.settingsAbout.localized) {
                    Text(L10n.settingsAboutBody.localized)
                        .font(.footnote)
                        .foregroundStyle(Theme.shell.metadata)
                }
                .listRowBackground(Color.white)
            }
            .scrollContentBackground(.hidden)
            .histudyShellBackground()
            .navigationTitle(L10n.settingsTitle.localized)
            .onAppear { localOfficials = appState.profile.localOfficials }
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { appState.profile.uiLanguage },
            set: { newValue in
                appState.profile.uiLanguage = newValue
                LocalizationManager.shared.setLanguage(newValue)
                PersistenceController.shared.save()
            }
        )
    }

    private var dailyGoalBinding: Binding<Int> {
        Binding(
            get: { appState.profile.dailyGoalMinutes },
            set: { newValue in
                appState.profile.dailyGoalMinutes = newValue
                PersistenceController.shared.save()
            }
        )
    }

    private var stateBinding: Binding<String> {
        Binding(
            get: { localOfficials.stateName ?? "" },
            set: { newValue in
                localOfficials.stateName = newValue.isEmpty ? nil : newValue
                persistLocalOfficials()
            }
        )
    }

    private func fieldBinding(_ keyPath: WritableKeyPath<LocalOfficialsProfile, String?>) -> Binding<String> {
        Binding(
            get: { localOfficials[keyPath: keyPath] ?? "" },
            set: { newValue in
                localOfficials[keyPath: keyPath] = newValue.isEmpty ? nil : newValue
                persistLocalOfficials()
            }
        )
    }

    private func persistLocalOfficials() {
        appState.profile.localOfficials = localOfficials
        PersistenceController.shared.save()
    }
}
