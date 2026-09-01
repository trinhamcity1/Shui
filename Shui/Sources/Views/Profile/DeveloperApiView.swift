import SwiftUI
import UIKit

@MainActor
final class DeveloperApiViewModel: ObservableObject {
    @Published private(set) var keys: [ApiKeyInfo] = []
    @Published private(set) var isLoading = false
    @Published var newKeyLabel = ""
    /// Set only in the instant right after `createKey()` succeeds — the raw
    /// key exists nowhere else, ever, once this is dismissed (phase-07 §8).
    @Published private(set) var justCreatedRawKey: String?
    @Published var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        keys = (try? await environment.apiKeys.listKeys()) ?? []
    }

    var canCreate: Bool {
        !newKeyLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func createKey() async {
        let label = newKeyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        do {
            let (_, rawKey) = try await environment.apiKeys.createKey(label: label)
            justCreatedRawKey = rawKey
            newKeyLabel = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissRawKey() {
        justCreatedRawKey = nil
    }

    func revoke(_ key: ApiKeyInfo) async {
        do {
            try await environment.apiKeys.revokeKey(keyId: key.keyId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// phase-07 §8 — self-serve key management, no tier gate. Documentation for
/// the API itself lives at `functions/docs/developer-api.md`, not in-app.
struct DeveloperApiView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @StateObject private var viewModel: DeveloperApiViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: DeveloperApiViewModel(environment: environment))
    }

    var body: some View {
        List {
            Section {
                TextField("Key label (e.g. \"My script\")", text: $viewModel.newKeyLabel)
                Button("Create key") { Task { await viewModel.createKey() } }
                    .disabled(!viewModel.canCreate)
            } footer: {
                Text("Requests $4/min of your own credit balance and your account's current tier settings — see the API reference for details.")
            }

            if !viewModel.keys.isEmpty {
                Section("Your keys") {
                    ForEach(viewModel.keys) { key in
                        keyRow(key)
                    }
                }
            }
        }
        .navigationTitle("Developer API")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert(
            "New key created",
            isPresented: Binding(get: { viewModel.justCreatedRawKey != nil }, set: { if !$0 { viewModel.dismissRawKey() } })
        ) {
            Button("Copy") {
                UIPasteboard.general.string = viewModel.justCreatedRawKey
                viewModel.dismissRawKey()
            }
            Button(Strings.done, role: .cancel) { viewModel.dismissRawKey() }
        } message: {
            Text("\(viewModel.justCreatedRawKey ?? "")\n\nCopy it now — Shui only stores its hash, so this is the only time you'll see it.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button(Strings.done, role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func keyRow(_ key: ApiKeyInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(key.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(key.revoked ? theme.textTertiary : theme.textPrimary)
                    .strikethrough(key.revoked)
                Spacer()
                if key.revoked {
                    Text("Revoked").font(.caption).foregroundStyle(theme.error)
                }
            }
            if let createdAt = key.createdAt {
                Text("Created \(createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
            }
            Text(key.lastUsedAt.map { "Last used \($0.formatted(date: .abbreviated, time: .shortened)) · \(key.requestCount) requests" }
                 ?? "Never used")
                .font(.caption2)
                .foregroundStyle(theme.textTertiary)
        }
        .swipeActions(edge: .trailing) {
            if !key.revoked {
                Button("Revoke", role: .destructive) { Task { await viewModel.revoke(key) } }
            }
        }
    }
}
