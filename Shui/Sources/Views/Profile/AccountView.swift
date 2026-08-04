import SwiftUI

/// Sign out, delete account, and linked sign-in providers — required by App
/// Review since account deletion is offered.
struct AccountView: View {
    let environment: AppEnvironment
    @Binding var isPresented: Bool
    @Environment(\.theme) private var theme

    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showSignInSheet = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Linked sign-in methods") {
                if environment.isGuest {
                    Text("Signed in as guest — sign in to keep your progress if you switch devices.")
                        .foregroundStyle(theme.textSecondary)
                    Button("Sign in") { showSignInSheet = true }
                        .foregroundStyle(theme.accent)
                } else if environment.auth.linkedProviderIDs.isEmpty {
                    Text("No linked providers.")
                        .foregroundStyle(theme.textSecondary)
                } else {
                    ForEach(environment.auth.linkedProviderIDs, id: \.self) { providerID in
                        Label(providerLabel(providerID), systemImage: providerIcon(providerID))
                            .foregroundStyle(theme.textPrimary)
                    }
                }
            }

            if !environment.isGuest {
                Section {
                    Button("Sign out") { showSignOutConfirm = true }
                        .foregroundStyle(theme.error)
                }
            }

            Section {
                Button("Delete account", role: .destructive) { showDeleteConfirm = true }
            } footer: {
                Text("Permanently deletes your account, progress, and likes. Your comments stay in place but show as posted by a deleted user.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(theme.error)
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .overlay {
            if isBusy { ProgressView() }
        }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await signOut() } }
        }
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            Button(Strings.cancel, role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This can't be undone.")
        }
        .sheet(isPresented: $showSignInSheet) { SignInSheet() }
    }

    private func providerLabel(_ providerID: String) -> String {
        switch providerID {
        case "apple.com": return "Apple"
        case "password": return "Email"
        case "anonymous": return "Guest"
        default: return providerID
        }
    }

    private func providerIcon(_ providerID: String) -> String {
        switch providerID {
        case "apple.com": return "apple.logo"
        case "password": return "envelope"
        default: return "person"
        }
    }

    private func signOut() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try environment.auth.signOut()
            await environment.bootstrapSession()
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await environment.auth.deleteAccount()
            await environment.bootstrapSession()
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
