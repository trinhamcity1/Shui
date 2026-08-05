import SwiftUI

/// Admin-only surface (prompts/phase-05-creator-mode.md §6). Reached from
/// Creator home, which itself only appears for creator/admin — but every
/// action behind these screens is independently enforced server-side, so a
/// hidden entry point is convenience, not protection.
struct AdminHomeView: View {
    let environment: AppEnvironment

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ReportsQueueView(environment: environment)
                } label: {
                    Label("Reports queue", systemImage: "flag")
                }
                NavigationLink {
                    AllTopicsView(environment: environment)
                } label: {
                    Label("All topics", systemImage: "square.stack.3d.up")
                }
                NavigationLink {
                    RoleManagementView(environment: environment)
                } label: {
                    Label("Roles", systemImage: "person.badge.key")
                }
                NavigationLink {
                    CategoryManagementView(environment: environment)
                } label: {
                    Label("Categories", systemImage: "square.grid.2x2")
                }
            }
        }
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Reports

private struct ReportsQueueView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @State private var reports: [ContentReport] = []
    @State private var isLoading = false
    @State private var noteDrafts: [String: String] = [:]
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section { Text(errorMessage).font(.subheadline).foregroundStyle(theme.error) }
            }
            if reports.isEmpty && !isLoading {
                Section {
                    Label("Nothing reported", systemImage: "checkmark.circle")
                        .foregroundStyle(theme.textSecondary)
                }
            }
            ForEach(reports) { report in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(report.reason)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        if let note = report.note, !note.isEmpty {
                            Text("\"\(note)\"")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Text(report.targetType.capitalized)
                            .font(.caption2)
                            .foregroundStyle(theme.textTertiary)
                    }

                    // The reported thing in context, not just its path —
                    // a moderator can't judge a comment without seeing it.
                    ReportedContentPreview(report: report, environment: environment)

                    TextField("Note (optional)", text: noteBinding(for: report))
                        .font(.caption)

                    HStack {
                        Button("Dismiss") {
                            Task { await act(report, .dismiss) }
                        }
                        Spacer()
                        Button("Delete content", role: .destructive) {
                            Task { await act(report, .deleteContent) }
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func noteBinding(for report: ContentReport) -> Binding<String> {
        Binding(
            get: { noteDrafts[report.id ?? ""] ?? "" },
            set: { noteDrafts[report.id ?? ""] = $0 }
        )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            reports = try await environment.admin.openReports(limit: 50)
        } catch {
            errorMessage = "Couldn't load the reports queue."
        }
    }

    private func act(_ report: ContentReport, _ action: ReportAction) async {
        guard let id = report.id else { return }
        do {
            try await environment.admin.action(reportId: id, action: action, note: noteDrafts[id])
            noteDrafts[id] = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Loads whichever kind of thing was reported. Both shapes resolve to a
/// video, so the video's title is always shown; a reported comment
/// additionally shows its text.
private struct ReportedContentPreview: View {
    @Environment(\.theme) private var theme
    let report: ContentReport
    let environment: AppEnvironment
    @State private var videoTitle: String?
    @State private var commentText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let videoTitle {
                Label(videoTitle, systemImage: "play.rectangle")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            if let commentText {
                Text(commentText)
                    .font(.subheadline)
                    .foregroundStyle(theme.textPrimary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surfaceSubtle))
            }
            if videoTitle == nil && commentText == nil {
                Text(report.targetPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let videoId = report.videoId else { return }
        videoTitle = (try? await environment.videos.video(id: videoId))?.title
        if let commentId = report.commentId {
            let page = try? await environment.social.comments(forVideo: videoId, limit: 200, after: nil)
            commentText = page?.items.first { $0.id == commentId }?.text
        }
    }
}

// MARK: - All topics

private struct AllTopicsView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @State private var topics: [Topic] = []
    @State private var creatorFilter = ""

    private var filtered: [Topic] {
        guard !creatorFilter.isEmpty else { return topics }
        return topics.filter { $0.createdByName.localizedCaseInsensitiveContains(creatorFilter) }
    }

    var body: some View {
        List {
            ForEach(filtered) { topic in
                NavigationLink {
                    TopicEditorView(topicId: topic.id, environment: environment)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(topic.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        HStack(spacing: 6) {
                            Text(topic.createdByName.isEmpty ? "Unknown creator" : topic.createdByName)
                            Text("·")
                            Text(topic.visibility == .public ? "Public" : "Private")
                        }
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
        .searchable(text: $creatorFilter, prompt: "Filter by creator")
        .navigationTitle("All topics")
        .navigationBarTitleDisplayMode(.inline)
        .task { topics = (try? await environment.topics.allTopics(limit: 200)) ?? [] }
    }
}

// MARK: - Roles

private struct RoleManagementView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var results: [UserAccount] = []
    @State private var pendingGrant: (user: UserAccount, role: UserAccount.Role)?
    @State private var message: String?
    @State private var isSearching = false

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Handle or name", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                    Button("Search") { Task { await search() } }
                        .font(.caption)
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if isSearching { ProgressView() }
            } footer: {
                // Said plainly rather than leaving an admin to wonder why an
                // email search found nothing: emails live in Firebase Auth,
                // which a client cannot query.
                Text("Searches handles and display names. Email lookup isn't possible from the app — emails live in Firebase Auth, not Firestore.")
            }

            if let message {
                Section { Text(message).font(.subheadline).foregroundStyle(theme.textSecondary) }
            }

            ForEach(results) { user in
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName).font(.subheadline.weight(.semibold))
                        Text("@\(user.handle)").font(.caption).foregroundStyle(theme.textSecondary)
                        Text("Currently: \(user.role.rawValue)").font(.caption).foregroundStyle(theme.textTertiary)
                    }
                    if user.role != .creator {
                        Button("Grant creator") { pendingGrant = (user, .creator) }
                    }
                    if user.role != .learner {
                        Button("Revoke to learner", role: .destructive) { pendingGrant = (user, .learner) }
                    }
                }
            }
        }
        .navigationTitle("Roles")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(get: { pendingGrant != nil }, set: { if !$0 { pendingGrant = nil } }),
            titleVisibility: .visible
        ) {
            Button(pendingGrant?.role == .learner ? "Revoke" : "Grant",
                   role: pendingGrant?.role == .learner ? .destructive : nil) {
                if let pendingGrant { Task { await assign(pendingGrant.user, pendingGrant.role) } }
                pendingGrant = nil
            }
            Button(Strings.cancel, role: .cancel) { pendingGrant = nil }
        } message: {
            Text(pendingGrant?.role == .creator
                 ? "This lets them publish content to every learner in the app."
                 : "They'll lose the ability to publish.")
        }
    }

    /// Names the user in the confirmation — granting publishing rights to
    /// the wrong account is exactly the mistake a generic "Are you sure?"
    /// fails to prevent (§6).
    private var confirmTitle: String {
        guard let pendingGrant else { return "" }
        let verb = pendingGrant.role == .learner ? "Revoke creator from" : "Grant creator to"
        return "\(verb) @\(pendingGrant.user.handle)?"
    }

    private func search() async {
        isSearching = true
        message = nil
        defer { isSearching = false }
        var found: [UserAccount] = []
        if let exact = try? await environment.admin.findUser(byHandle: query), exact.id != nil {
            found.append(exact)
        }
        let byName = (try? await environment.admin.findUser(byEmailPrefix: query)) ?? []
        for user in byName where !found.contains(where: { $0.id == user.id }) {
            found.append(user)
        }
        results = found
        if found.isEmpty { message = "No one matched that." }
    }

    private func assign(_ user: UserAccount, _ role: UserAccount.Role) async {
        guard let uid = user.id else { return }
        do {
            try await environment.admin.assignRole(uid: uid, role: role)
            message = "@\(user.handle) is now \(role.rawValue). They'll see the change the next time they open the app."
            await search()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Categories

private struct CategoryManagementView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @State private var categories: [Category] = []
    @State private var editing: Category?
    @State private var isCreating = false

    var body: some View {
        List {
            ForEach(categories) { category in
                Button {
                    editing = category
                } label: {
                    HStack {
                        Image(systemName: category.sfSymbol)
                            .foregroundStyle(theme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.title).foregroundStyle(theme.textPrimary)
                            Text("\(category.topicCount) topics · order \(category.sortOrder)")
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        if !category.isActive {
                            Text("Hidden").font(.caption2).foregroundStyle(theme.textTertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isCreating = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { category in
            CategoryEditorSheet(category: category, environment: environment)
        }
        .sheet(isPresented: $isCreating, onDismiss: { Task { await load() } }) {
            CategoryEditorSheet(category: nil, environment: environment)
        }
    }

    private func load() async {
        categories = (try? await environment.categories.list()) ?? []
    }
}

private struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    let category: Category?
    let environment: AppEnvironment

    @State private var title: String
    @State private var description: String
    @State private var sfSymbol: String
    @State private var accentHex: String
    @State private var sortOrder: Int
    @State private var isActive: Bool
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(category: Category?, environment: AppEnvironment) {
        self.category = category
        self.environment = environment
        _title = State(initialValue: category?.title ?? "")
        _description = State(initialValue: category?.description ?? "")
        _sfSymbol = State(initialValue: category?.sfSymbol ?? "square.grid.2x2")
        _accentHex = State(initialValue: category?.accentHex ?? "22C55E")
        _sortOrder = State(initialValue: category?.sortOrder ?? 0)
        _isActive = State(initialValue: category?.isActive ?? true)
    }

    private var isValid: Bool {
        title.trimmingCharacters(in: .whitespaces).count >= 2
            && accentHex.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
            && !sfSymbol.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                    HStack {
                        TextField("SF Symbol", text: $sfSymbol)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Image(systemName: sfSymbol)
                            .foregroundStyle(theme.accent)
                    }
                    HStack {
                        TextField("Accent hex", text: $accentHex)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("no #").font(.caption2).foregroundStyle(theme.textTertiary)
                    }
                    Stepper("Sort order: \(sortOrder)", value: $sortOrder, in: 0...999)
                    Toggle("Visible to learners", isOn: $isActive)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.subheadline).foregroundStyle(theme.error)
                    }
                }
            }
            .navigationTitle(category == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.save) { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await environment.admin.saveCategory(
                categoryId: category?.id,
                title: title.trimmingCharacters(in: .whitespaces),
                description: description,
                sfSymbol: sfSymbol,
                accentHex: accentHex.uppercased(),
                sortOrder: sortOrder,
                isActive: isActive
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
