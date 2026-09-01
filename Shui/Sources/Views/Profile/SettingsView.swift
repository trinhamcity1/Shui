import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment
    /// Bound to the same state `ProfileView` uses to present this sheet —
    /// threaded down to `AccountView` so a sign-out or account deletion can
    /// close the whole sheet in one step, not just pop its own nav push.
    @Binding var isPresented: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Account") {
                        AccountView(environment: environment, isPresented: $isPresented)
                    }
                    comingSoonRow("Notifications", phase: 6)
                }
                Section {
                    NavigationLink("Balance & plan") {
                        BillingView(environment: environment)
                    }
                    // Self-serve, no tier gate (phase-07 §8) — every account
                    // can mint a key, unlike the Creator section below.
                    NavigationLink("Developer API") {
                        DeveloperApiView(environment: environment)
                    }
                }
                Section {
                    NavigationLink("About") {
                        AboutView()
                    }
                    comingSoonRow("Privacy Policy", phase: nil)
                    comingSoonRow("Terms of Service", phase: nil)
                }
                // Gated on the ID token's claim, not `currentUser.role` (a
                // Firestore display mirror) — and refreshed on foreground,
                // so a just-granted role appears here without a reinstall.
                if environment.isCreator {
                    Section {
                        NavigationLink("Creator") {
                            CreatorHomeView(environment: environment)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { isPresented = false }
                }
            }
        }
    }

    private func comingSoonRow(_ title: String, phase: Int?) -> some View {
        HStack {
            Text(title).foregroundStyle(theme.textTertiary)
            Spacer()
            Text(phase.map { "Phase \($0)" } ?? "Coming soon")
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
        }
    }
}

private struct AboutView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.accent)
                Text("Shui")
                    .font(.title2.bold())
                    .foregroundStyle(theme.textPrimary)
                Text("Short videos that teach you something, then check you learned it. No infinite scroll, no streak guilt — when knowledge retention and session retention conflict, knowledge wins.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 40)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .shuiShellBackground()
    }
}
