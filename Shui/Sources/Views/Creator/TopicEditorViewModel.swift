import Foundation

/// Field-level validation mirroring `prompts/phase-05-creator-mode.md` §3's
/// table. Kept as pure functions on the view model so the Save button's
/// enabled state and the inline field errors can't disagree.
struct TopicFieldErrors {
    var title: String?
    var subtitle: String?
    var description: String?
    var category: String?

    var isEmpty: Bool { title == nil && subtitle == nil && description == nil && category == nil }
}

@MainActor
final class TopicEditorViewModel: ObservableObject {
    // Form state
    @Published var title: String
    @Published var subtitle: String
    @Published var description: String
    @Published var categoryId: String
    @Published var tags: [String]
    @Published var coverImageURL: String?

    // Loaded context
    @Published private(set) var topicId: String?
    @Published private(set) var visibility: Topic.Visibility
    @Published private(set) var videos: [Video] = []
    @Published private(set) var categories: [Category] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let environment: AppEnvironment
    private var loadedTopic: Topic?

    init(topicId: String?, draftTopic: Topic?, environment: AppEnvironment) {
        self.environment = environment
        self.topicId = topicId
        let seed = draftTopic
        title = seed?.title ?? ""
        subtitle = seed?.subtitle ?? ""
        description = seed?.description ?? ""
        categoryId = seed?.categoryId ?? ""
        tags = seed?.tags ?? []
        coverImageURL = seed?.coverImageURL
        visibility = seed?.visibility ?? .private
        loadedTopic = draftTopic
    }

    var isNew: Bool { topicId == nil }

    var readyVideos: [Video] { videos.filter { $0.status == .ready && !$0.isDeleted } }
    var canPublish: Bool { !readyVideos.isEmpty }

    /// Videos eligible to go public in one tap — ready and quizzed, just not
    /// individually public yet.
    var publishableVideos: [Video] { readyVideos.filter { $0.hasQuiz && $0.visibility != .public } }

    /// True exactly in the state that confuses a first-time creator: the
    /// topic itself is discoverable, but a learner who opens it sees nothing
    /// because visibility is two-level — a topic being public only makes it
    /// *findable*, each video inside still needs its own visibility flipped.
    /// `setTopicVisibility`'s publish gate only checks that a ready video
    /// exists, not that one is actually public, so this state is reachable
    /// through the normal flow, not a misuse.
    var isPublishedWithNothingVisible: Bool {
        visibility == .public && !videos.contains { $0.visibility == .public }
    }

    /// Shown inline in the editor, before Publish is tapped. The Function
    /// enforces the same rule and its message is surfaced verbatim on
    /// failure — this exists so that failure is never the first time the
    /// creator learns about it (§3).
    var publishChecklist: [(text: String, satisfied: Bool)] {
        [
            ("At least one video finished uploading", !readyVideos.isEmpty),
            ("Every ready video has a quiz", readyVideos.allSatisfy(\.hasQuiz)),
            ("Cover image set", coverImageURL != nil),
        ]
    }

    var fieldErrors: TopicFieldErrors {
        var errors = TopicFieldErrors()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            errors.title = "Title is required."
        } else if trimmedTitle.count < 3 {
            errors.title = "Title must be at least 3 characters."
        } else if trimmedTitle.count > 80 {
            errors.title = "Title must be 80 characters or fewer."
        }

        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSubtitle.isEmpty {
            errors.subtitle = "Subtitle is required."
        } else if trimmedSubtitle.count > 120 {
            errors.subtitle = "Subtitle must be 120 characters or fewer."
        }

        if description.count > 4000 {
            errors.description = "Description must be 4000 characters or fewer."
        }
        if categoryId.isEmpty {
            errors.category = "Pick a category."
        }
        return errors
    }

    var canSave: Bool { fieldErrors.isEmpty && !isSaving }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        categories = (try? await environment.categories.list()) ?? []

        if let topicId {
            if let topic = try? await environment.topics.topic(id: topicId) {
                apply(topic)
            }
            await reloadVideos()
        }
        if let draft = CreatorDraftStore.topicDraft(topicId: topicId) {
            recoverableDraft = draft
        }
    }

    func reloadVideos() async {
        guard let topicId else { return }
        videos = (try? await environment.videos.allVideos(inTopic: topicId)) ?? []
    }

    private func apply(_ topic: Topic) {
        loadedTopic = topic
        title = topic.title
        subtitle = topic.subtitle
        description = topic.description
        categoryId = topic.categoryId ?? ""
        tags = topic.tags
        coverImageURL = topic.coverImageURL
        visibility = topic.visibility
    }

    /// Returns the saved topic's id so a brand-new topic can immediately
    /// continue into the upload flow without a round trip through the
    /// dashboard.
    @discardableResult
    func save() async -> String? {
        guard canSave else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        var payload = loadedTopic ?? Topic.newDraft(
            createdBy: environment.auth.currentUID ?? "",
            createdByName: environment.currentUser?.displayName ?? ""
        )
        payload.id = topicId
        payload.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.description = description
        payload.categoryId = categoryId
        payload.tags = tags
        payload.coverImageURL = coverImageURL

        do {
            if topicId == nil {
                let created = try await environment.topics.create(payload)
                topicId = created.id
                loadedTopic = created
            } else {
                try await environment.topics.update(payload)
                loadedTopic = payload
            }
            // Cleared only after the server accepted the write. A new topic's
            // draft lives under the "__new__" slot until it has an id, so
            // both are cleared here.
            CreatorDraftStore.clearTopicDraft(topicId: nil)
            CreatorDraftStore.clearTopicDraft(topicId: topicId)
            recoverableDraft = nil
            successMessage = "Saved."
            return topicId
        } catch {
            errorMessage = "Couldn't save this topic. Your changes are kept on this device — try again when you're back online."
            return nil
        }
    }

    // MARK: - Offline drafts

    @Published private(set) var recoverableDraft: CreatorDraftStore.TopicDraft?

    func persistDraftLocally() {
        CreatorDraftStore.saveTopicDraft(
            CreatorDraftStore.TopicDraft(
                title: title,
                subtitle: subtitle,
                description: description,
                categoryId: categoryId,
                tags: tags,
                savedAt: Date()
            ),
            topicId: topicId
        )
    }

    func restoreDraft() {
        guard let draft = recoverableDraft else { return }
        title = draft.title
        subtitle = draft.subtitle
        description = draft.description
        categoryId = draft.categoryId
        tags = draft.tags
        recoverableDraft = nil
    }

    func discardDraft() {
        CreatorDraftStore.clearTopicDraft(topicId: topicId)
        recoverableDraft = nil
    }

    func setVisibility(_ next: Topic.Visibility) async {
        guard let topicId else { return }
        errorMessage = nil
        do {
            try await environment.topics.setVisibility(topicId: topicId, visibility: next)
            visibility = next
            successMessage = next == .public ? "Published." : "Unpublished."
        } catch {
            // The publish gate's message is the actual explanation ("no ready
            // videos yet") — surface it verbatim rather than replacing it
            // with a generic failure, per §3.
            errorMessage = error.localizedDescription
        }
    }

    func reorder(from source: IndexSet, to destination: Int) async {
        guard let topicId else { return }
        var reordered = videos
        reordered.move(fromOffsets: source, toOffset: destination)
        // Optimistic, then reverted on rejection — "optimistic but honest"
        // from §7. The list must move under the finger immediately or drag
        // reordering feels broken.
        let previous = videos
        videos = reordered
        do {
            try await environment.videos.reorder(topicId: topicId, videoIds: reordered.compactMap(\.id))
        } catch {
            videos = previous
            errorMessage = "Couldn't save the new order. It's been put back."
        }
    }

    func deleteVideo(_ video: Video) async {
        guard let videoId = video.id else { return }
        do {
            try await environment.videos.softDelete(videoId: videoId)
            await reloadVideos()
        } catch {
            errorMessage = "Couldn't remove that video."
        }
    }

    func setVideoVisibility(_ video: Video, to next: Video.Visibility) async {
        guard let videoId = video.id else { return }
        do {
            try await environment.videos.setVisibility(videoId: videoId, visibility: next)
            await reloadVideos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The one-tap fix for `isPublishedWithNothingVisible` — makes every
    /// eligible video public. Runs sequentially rather than concurrently:
    /// this is a handful of videos at most, and a clear error on which one
    /// failed matters more here than shaving off a second.
    func publishAllEligibleVideos() async {
        for video in publishableVideos {
            guard let videoId = video.id else { continue }
            do {
                try await environment.videos.setVisibility(videoId: videoId, visibility: .public)
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        await reloadVideos()
    }

    func softDeleteTopic() async -> Bool {
        guard let topicId else { return false }
        do {
            try await environment.topics.softDelete(topicId: topicId)
            return true
        } catch {
            errorMessage = "Couldn't delete this topic."
            return false
        }
    }

    func duplicateTopic() async {
        guard let loadedTopic else { return }
        do {
            _ = try await environment.topics.duplicate(loadedTopic)
            successMessage = "Duplicated. The copy is in your drafts."
        } catch {
            errorMessage = "Couldn't duplicate this topic."
        }
    }

    func uploadCover(_ jpegData: Data) async {
        guard let topicId else {
            errorMessage = "Save this topic first, then add a cover image."
            return
        }
        do {
            let ticket = try await environment.uploads.createTopicCoverUpload(topicId: topicId, sizeBytes: jpegData.count)
            try await environment.uploads.uploadData(jpegData, to: ticket.uploadURL, contentType: "image/jpeg")
            coverImageURL = ticket.coverImageURL
            // Persist immediately rather than waiting for Save — the bytes
            // are already in R2 at this point, so leaving the reference
            // unsaved is the one state that would actually lose work.
            await save()
        } catch {
            errorMessage = "Couldn't upload that cover image."
        }
    }

    func addTag(_ raw: String) {
        let normalized = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard !normalized.isEmpty, !tags.contains(normalized), tags.count < 8 else { return }
        tags.append(normalized)
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}
