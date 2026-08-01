import SwiftUI

struct EditProfileSheet: View {
    let environment: AppEnvironment
    let account: UserAccount?
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var handle: String
    @State private var bio: String
    @State private var isBusy = false
    @State private var errorMessage: String?

    init(environment: AppEnvironment, account: UserAccount?) {
        self.environment = environment
        self.account = account
        _displayName = State(initialValue: account?.displayName ?? "")
        _handle = State(initialValue: account?.handle ?? "")
        _bio = State(initialValue: account?.bio ?? "")
    }

    private var isHandleValid: Bool {
        handle.count >= 3 && handle.count <= 20 && handle.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display name") {
                    TextField("Display name", text: $displayName)
                }
                Section("Handle") {
                    HStack {
                        Text("@").foregroundStyle(theme.textSecondary)
                        TextField("handle", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: handle) { _, newValue in
                                handle = String(newValue.lowercased().filter { $0.isLowercase || $0.isNumber || $0 == "_" }.prefix(20))
                            }
                    }
                    if !handle.isEmpty && !isHandleValid {
                        Text("3-20 characters: lowercase letters, numbers, underscores.")
                            .font(.caption)
                            .foregroundStyle(theme.error)
                    }
                }
                Section("Bio") {
                    TextField("Tell other learners about yourself", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(theme.error)
                    }
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.save) { Task { await save() } }
                        .disabled(isBusy || displayName.trimmingCharacters(in: .whitespaces).isEmpty || (!handle.isEmpty && !isHandleValid))
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
    }

    private func save() async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            try await environment.users.updateProfile(displayName: displayName, bio: bio, interests: nil)
            if !handle.isEmpty, handle != account?.handle {
                try await environment.users.claimHandle(handle)
            }
            await environment.refreshCurrentUser()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
