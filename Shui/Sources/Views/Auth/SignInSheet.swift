import AuthenticationServices
import SwiftUI

/// The upgrade-prompt sheet — presented at the moment of need (liking,
/// commenting, opening the AI tutor), never as a launch modal. Offers Apple
/// first per Apple's HIG (required since a third-party sign-in is offered),
/// then email. Both paths funnel into the same outcome handling: a genuinely
/// new account gets a display-name/handle prompt next, while landing on an
/// account that already existed (rather than upgrading the current guest)
/// gets an explicit "your guest progress didn't transfer" notice instead of
/// silently dropping it.
struct SignInSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var currentNonce: String?
    @State private var showEmailForm = false
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showMergeNotice = false
    @State private var namePromptSuggestion: NamePromptSuggestion?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 40))
                        .foregroundStyle(theme.accent)
                    Text("Sign in to continue")
                        .font(.title3.bold())
                        .foregroundStyle(theme.textPrimary)
                    Text("Your progress as a guest carries over automatically.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(theme.error)
                        .multilineTextAlignment(.center)
                }

                SignInWithAppleButton(.signIn, onRequest: configureAppleRequest, onCompletion: handleAppleCompletion)
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(isBusy)

                if showEmailForm {
                    emailForm
                } else {
                    Button("Continue with email") {
                        withAnimation { showEmailForm = true }
                    }
                    .buttonStyle(.shuiPillOutline)
                    .disabled(isBusy)
                }

                if isBusy {
                    ProgressView()
                }

                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $namePromptSuggestion) { suggestion in
            DisplayNameHandleSheet(suggestedName: suggestion.name) { dismiss() }
        }
        .alert("Signed into an existing account", isPresented: $showMergeNotice) {
            Button(Strings.done, role: .cancel) { dismiss() }
        } message: {
            Text("That sign-in already had an account, so we signed you into it instead. Progress you made as a guest on this device didn't transfer.")
        }
    }

    private var emailForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surfaceSubtle))
            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surfaceSubtle))

            Button("Continue") { Task { await submitEmail() } }
                .buttonStyle(.shuiPill)
                .disabled(email.isEmpty || password.count < 6 || isBusy)

            Button("Forgot password?") { Task { await sendReset() } }
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
                .disabled(email.isEmpty || isBusy)
        }
    }

    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleNonce.random()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(nonce)
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result else {
            if case .failure(let error) = result, (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
            return
        }
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            errorMessage = "Apple sign-in didn't return a usable credential."
            return
        }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let result = try await environment.auth.signInWithApple(idToken: idToken, rawNonce: nonce, fullName: credential.fullName)
                await handleUpgrade(result, method: "apple")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submitEmail() async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            let result = try await environment.auth.continueWithEmail(email: email, password: password)
            await handleUpgrade(result, method: "email")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendReset() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await environment.auth.sendPasswordReset(email: email)
            errorMessage = "Password reset email sent."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleUpgrade(_ result: AuthUpgradeResult, method: String) async {
        switch result.outcome {
        case .linked:
            // Almost always a no-op: linking keeps the same uid, and that
            // uid's profile doc already exists from the guest session's own
            // bootstrap at launch. Only matters for the rare case of a link
            // happening with no prior guest session at all.
            try? await environment.users.createProfileIfNeeded(
                displayName: result.suggestedDisplayName ?? "Learner",
                photoURL: nil,
                authProviders: environment.auth.linkedProviderIDs,
                isGuest: false
            )
            await environment.refreshCurrentUser()
            // The ID token minted for this sign-in already carries whatever
            // role this account has — but `environment.role` itself is a
            // separate cached value that otherwise only updates on
            // foreground. Without this, a guest who signs into an existing
            // creator/admin account keeps seeing the learner-only UI until
            // the app is backgrounded and reopened.
            await environment.refreshRole(forceRefresh: true)
            AppAnalytics.logSignInCompleted(method: method)
            // An empty handle is the reliable "never claimed one" signal —
            // more so than Firebase's isNewUser, which describes whether
            // the credential itself is new, not whether this account has
            // ever been through the name/handle prompt. A guest who used
            // the app for a week before finally signing in still needs it.
            if environment.currentUser?.handle.isEmpty ?? true {
                namePromptSuggestion = NamePromptSuggestion(name: result.suggestedDisplayName ?? "")
            } else {
                dismiss()
            }
        case .signedIntoExistingAccount:
            await environment.refreshCurrentUser()
            await environment.refreshRole(forceRefresh: true)
            AppAnalytics.logSignInCompleted(method: method)
            showMergeNotice = true
        }
    }
}

private struct NamePromptSuggestion: Identifiable {
    let name: String
    var id: String { name }
}

/// Shown right after a brand-new account's first real sign-in — Apple only
/// ever provides a full name once, and a fresh email account has no name at
/// all, so this is the one chance to collect both before the moment passes.
private struct DisplayNameHandleSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.theme) private var theme
    let suggestedName: String
    let onDone: () -> Void

    @State private var displayName: String
    @State private var handle = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    init(suggestedName: String, onDone: @escaping () -> Void) {
        self.suggestedName = suggestedName
        self.onDone = onDone
        _displayName = State(initialValue: suggestedName)
    }

    private var isHandleValid: Bool {
        handle.count >= 3 && handle.count <= 20 && handle.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("What should we call you?")
                    .font(.title3.bold())
                    .foregroundStyle(theme.textPrimary)

                TextField("Display name", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surfaceSubtle))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(theme.textSecondary)
                        TextField("handle", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: handle) { _, newValue in
                                handle = String(newValue.lowercased().filter { $0.isLowercase || $0.isNumber || $0 == "_" }.prefix(20))
                            }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surfaceSubtle))
                    Text("3-20 characters: lowercase letters, numbers, underscores.")
                        .font(.caption2)
                        .foregroundStyle(theme.textTertiary)
                }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(theme.error)
                }

                Button("Save") { Task { await save() } }
                    .buttonStyle(.shuiPill)
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || !isHandleValid || isBusy)

                Spacer()
            }
            .padding(24)
        }
        .interactiveDismissDisabled(isBusy)
    }

    private func save() async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            try await environment.users.updateProfile(displayName: displayName, bio: nil, interests: nil)
            try await environment.users.claimHandle(handle)
            await environment.refreshCurrentUser()
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
