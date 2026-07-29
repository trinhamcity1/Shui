import SwiftUI

/// Full-screen sign-in prompt shown after the learner completes two feed
/// lessons, followed by the free/pro tier choice.
///
/// Honest scoping: the provider buttons record the choice locally and mark
/// the profile signed in — real Google/Facebook/Instagram OAuth requires
/// provider app registrations plus Firebase Auth or Cognito (see README's
/// backend workstream). The flow, gating, and persistence are all real;
/// only the identity-provider round trip is simulated until then.
struct SignInPromptView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .providers
    private enum Step { case providers, tier }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            TutorLogoView(emotion: .happy, size: 88)

            switch step {
            case .providers:
                providersStep
            case .tier:
                TierPickerView(onDone: { dismiss() })
            }

            Spacer()
        }
        .padding()
        .shuiShellBackground()
        .interactiveDismissDisabled(step == .tier)
    }

    private var providersStep: some View {
        VStack(spacing: 16) {
            Text(L10n.signinTitle.localized)
                .font(.title2.bold())
                .foregroundStyle(Theme.shell.ink)
                .multilineTextAlignment(.center)
            Text(L10n.signinBody.localized)
                .font(.subheadline)
                .foregroundStyle(Theme.shell.metadata)
                .multilineTextAlignment(.center)

            providerButton(.google, symbol: "g.circle.fill", label: L10n.signinGoogle.localized)
            providerButton(.facebook, symbol: "f.circle.fill", label: L10n.signinFacebook.localized)
            providerButton(.instagram, symbol: "camera.circle.fill", label: L10n.signinInstagram.localized)

            Button(L10n.signinLater.localized) { dismiss() }
                .font(.subheadline)
                .tint(Theme.shell.metadata)
        }
    }

    private func providerButton(_ provider: AuthProvider, symbol: String, label: String) -> some View {
        Button {
            appState.profile.isSignedIn = true
            appState.profile.authProvider = provider
            PersistenceController.shared.save()
            withAnimation { step = .tier }
        } label: {
            HStack {
                Image(systemName: symbol)
                Text(label)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white, in: Capsule())
            .foregroundStyle(Theme.shell.ink)
        }
        .buttonStyle(.plain)
    }
}

/// Free vs. Pro choice, shown right after sign-in and reachable again from
/// the upgrade prompt.
struct TierPickerView: View {
    let onDone: () -> Void
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.tierTitle.localized)
                .font(.title2.bold())
                .foregroundStyle(Theme.shell.ink)

            tierCard(
                tier: .free,
                title: L10n.tierFreeTitle.localized,
                description: L10n.tierFreeDesc.localized
            )
            tierCard(
                tier: .pro,
                title: L10n.tierProTitle.localized,
                description: L10n.tierProDesc.localized
            )
        }
    }

    private func tierCard(tier: SubscriptionTier, title: String, description: String) -> some View {
        Button {
            appState.profile.subscriptionTier = tier
            PersistenceController.shared.save()
            onDone()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.shell.ink)
                    if tier == .pro {
                        Text(L10n.proBadge.localized)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.shell.accentGradient, in: Capsule())
                    }
                    Spacer()
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Theme.shell.metadata)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.shell.cornerRadiusCard, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Shown when a free-tier user taps a pro feature. "Upgrading" here sets
/// the tier locally — real payments require StoreKit products configured
/// in App Store Connect, which is part of the backend/infra workstream.
struct UpgradePromptView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            TutorLogoView(emotion: .celebrating, size: 72)
            Text(L10n.upgradeTitle.localized)
                .font(.title2.bold())
                .foregroundStyle(Theme.shell.ink)
                .multilineTextAlignment(.center)
            Text(L10n.upgradeBody.localized)
                .font(.subheadline)
                .foregroundStyle(Theme.shell.metadata)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L10n.upgradeCTA.localized) {
                appState.profile.subscriptionTier = .pro
                PersistenceController.shared.save()
                dismiss()
            }
            .buttonStyle(.shuiPill)
            Button(L10n.upgradeLater.localized) { dismiss() }
                .font(.subheadline)
                .tint(Theme.shell.metadata)
        }
        .padding()
        .shuiShellBackground()
    }
}
