import SwiftUI

/// Three skippable screens shown once, gating `RootTabView` until
/// `hasCompletedOnboarding` is set. Manual paging (not a swipeable
/// `.page` style) on purpose — the interests step needs to block advancing
/// until at least one category is picked, which a free-swipe page view
/// can't enforce.
struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.theme) private var theme
    @State private var step = 0
    @State private var selectedInterests: Set<String> = []
    @State private var categories: [Category] = []
    @State private var isSaving = false

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $step) {
                OnboardingIntroScreen().tag(0)
                OnboardingInterestsScreen(categories: categories, selected: $selectedInterests).tag(1)
                OnboardingQuizPreviewScreen().tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            footer
        }
        .shuiShellBackground()
        .task {
            categories = (try? await environment.categories.list()) ?? []
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button("Skip") { Task { await finish() } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
                .accessibilityLabel("Skip onboarding")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? theme.accent : theme.borderSubtle)
                        .frame(width: index == step ? 20 : 6, height: 6)
                        .animation(.easeInOut, value: step)
                }
            }
            Button(step == totalSteps - 1 ? "Get started" : "Continue") {
                Task { await advance() }
            }
            .buttonStyle(.shuiPill)
            .disabled(isSaving || (step == 1 && selectedInterests.isEmpty))
        }
        .padding(24)
    }

    private func advance() async {
        if step == 1 {
            await saveInterests()
        }
        if step < totalSteps - 1 {
            withAnimation { step += 1 }
        } else {
            await finish()
        }
    }

    private func saveInterests() async {
        isSaving = true
        defer { isSaving = false }
        await environment.bootstrapSession() // idempotent; guarantees a uid to write to
        let interests = Array(selectedInterests)
        appState.profile.selectedInterests = interests
        try? await environment.users.updateProfile(displayName: nil, bio: nil, interests: interests)
        await environment.refreshCurrentUser()
        AppAnalytics.logInterestsSelected(count: interests.count)
    }

    private func finish() async {
        appState.profile.hasCompletedOnboarding = true
        PersistenceController.shared.save()
    }
}

// MARK: - Screen 1

private struct OnboardingIntroScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 120, height: 120)
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(theme.textOnAccent)
            }
            VStack(spacing: 10) {
                Text("Welcome to Shui")
                    .font(.title.bold())
                    .foregroundStyle(theme.textPrimary)
                Text("Short videos that teach you something, then check you learned it.")
                    .font(.title3)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Screen 2

private struct OnboardingInterestsScreen: View {
    @Environment(\.theme) private var theme
    let categories: [Category]
    @Binding var selected: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick your interests")
                        .font(.title2.bold())
                        .foregroundStyle(theme.textPrimary)
                    Text("Pick at least one — this shapes what shows up first in your feed.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(categories) { category in
                        let isSelected = category.id.map(selected.contains) ?? false
                        Button {
                            guard let id = category.id else { return }
                            if isSelected {
                                selected.remove(id)
                            } else {
                                selected.insert(id)
                            }
                        } label: {
                            OnboardingCategoryTile(category: category, isSelected: isSelected)
                        }
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct OnboardingCategoryTile: View {
    @Environment(\.theme) private var theme
    let category: Category
    let isSelected: Bool

    private var accent: Color {
        Color(hex: UInt32(category.accentHex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0xB4530A)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: category.sfSymbol)
                    .font(.title3)
                    .foregroundStyle(accent)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            Text(category.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous)
                .fill(isSelected ? theme.accent.opacity(0.12) : theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous)
                .stroke(isSelected ? theme.accent : theme.borderSubtle, lineWidth: isSelected ? 2 : 1)
        )
    }
}

// MARK: - Screen 3

private struct OnboardingQuizPreviewScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 10) {
                Text("The quiz is the point")
                    .font(.title2.bold())
                    .foregroundStyle(theme.textPrimary)
                Text("Every video ends with a quick check. Miss a question and it comes back later — spaced out until it sticks.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Question 1 of 2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                Text("What's the point of the quiz?")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.textPrimary)
                VStack(spacing: 10) {
                    mockOption("To check what actually stuck", selected: true)
                    mockOption("To keep you scrolling", selected: false)
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusCard, style: .continuous).stroke(theme.borderSubtle, lineWidth: 1))
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
    }

    private func mockOption(_ text: String, selected: Bool) -> some View {
        HStack {
            Text(text)
                .font(.body)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? theme.accent.opacity(0.12) : theme.surfaceSubtle)
        )
    }
}
