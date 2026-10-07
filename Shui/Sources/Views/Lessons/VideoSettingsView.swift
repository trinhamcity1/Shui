import SwiftUI
import PhotosUI
import Photos

@MainActor
final class VideoSettingsViewModel: ObservableObject {
    @Published var video: Video
    @Published var title: String
    @Published private(set) var isSavingTitle = false
    @Published private(set) var isUploadingThumbnail = false
    @Published private(set) var isRegeneratingQuiz = false
    @Published private(set) var isTogglingShare = false
    @Published private(set) var isDeleting = false
    @Published private(set) var isDownloading = false
    @Published private(set) var canDownload = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published private(set) var deleted = false

    let environment: AppEnvironment

    init(video: Video, environment: AppEnvironment) {
        self.video = video
        self.title = video.title
        self.environment = environment
    }

    private var videoId: String? { video.id }

    func loadDownloadEntitlement() async {
        guard let wallet = try? await environment.billing.wallet() else { return }
        canDownload = TierInfo.info(for: wallet.tier).downloadable
    }

    func saveTitle() async {
        guard let videoId else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Title can't be empty."
            return
        }
        isSavingTitle = true
        errorMessage = nil
        successMessage = nil
        defer { isSavingTitle = false }
        do {
            try await environment.videos.updateMetadata(
                videoId: videoId, title: trimmed, description: nil, transcript: nil, thumbnailURL: nil
            )
            video.title = trimmed
            successMessage = "Title saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uploadThumbnail(_ jpegData: Data) async {
        guard let videoId else { return }
        isUploadingThumbnail = true
        errorMessage = nil
        successMessage = nil
        defer { isUploadingThumbnail = false }
        do {
            let ticket = try await environment.uploads.createThumbnailUpload(videoId: videoId, sizeBytes: jpegData.count)
            try await environment.uploads.uploadData(jpegData, to: ticket.uploadURL, contentType: "image/jpeg")
            try await environment.videos.updateMetadata(
                videoId: videoId, title: nil, description: nil, transcript: nil, thumbnailURL: ticket.thumbnailURL
            )
            video.thumbnailURL = ticket.thumbnailURL
            successMessage = "Thumbnail updated."
        } catch {
            errorMessage = "Couldn't upload that thumbnail."
        }
    }

    func regenerateQuiz() async {
        guard let videoId else { return }
        isRegeneratingQuiz = true
        errorMessage = nil
        successMessage = nil
        defer { isRegeneratingQuiz = false }
        do {
            let remaining = try await environment.onDemandLessons.regenerateQuiz(videoId: videoId)
            successMessage = remaining > 0
                ? "Quiz regenerated — \(remaining) more today."
                : "Quiz regenerated — that was today's last one."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var isShared: Bool { video.sharedToSocial == true }
    var canToggleShare: Bool { video.status == .ready && video.originatedFromApi != true }

    func toggleShare() async {
        guard let videoId else { return }
        isTogglingShare = true
        errorMessage = nil
        successMessage = nil
        defer { isTogglingShare = false }
        do {
            if isShared {
                try await environment.onDemandLessons.unshareFromSocial(videoId: videoId)
                video.sharedToSocial = false
                video.visibility = .private
                successMessage = "Made private."
            } else {
                AppAnalytics.logFeatureTap(.shareToSocial)
                try await environment.onDemandLessons.shareToSocial(videoId: videoId)
                video.sharedToSocial = true
                video.visibility = .public
                successMessage = "Shared to Social."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteVideo() async {
        guard let videoId else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await environment.videos.softDelete(videoId: videoId)
            deleted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Always the plain `playbackURL` — the app has no viewer-tier-aware
    /// watermarked/clean split wired in anywhere else yet (`FeedPageView`
    /// itself only ever reads `playbackURL` too), so this matches how every
    /// other screen already behaves rather than inventing a distinction
    /// nothing else honors.
    func downloadToPhotos() async {
        guard let urlString = video.playbackURL, let url = URL(string: urlString) else {
            errorMessage = "This lesson isn't ready to download yet."
            return
        }
        isDownloading = true
        errorMessage = nil
        successMessage = nil
        defer { isDownloading = false }
        do {
            let status = await Self.requestAddOnlyAuthorization()
            guard status == .authorized || status == .limited else {
                errorMessage = "Allow Photos access in Settings to save this video."
                return
            }
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            defer { try? FileManager.default.removeItem(at: destination) }
            try await Self.saveVideoToPhotos(fileURL: destination)
            successMessage = "Saved to Photos."
        } catch {
            errorMessage = "Couldn't save that video."
        }
    }

    /// `PHPhotoLibrary`'s APIs are completion-handler-based — wrapped in
    /// continuations rather than assumed to have a native async overload,
    /// since that can't be verified without a real build here.
    private static func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func saveVideoToPhotos(fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? RepositoryError.uploadFailed)
                }
            })
        }
    }
}

/// The settings page for one of the learner's own on-demand lessons —
/// reached by tapping the gear revealed by swiping a My Lessons row (see
/// `SwipeToRevealRow` in `MyLessonsView.swift`).
struct VideoSettingsView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: VideoSettingsViewModel
    @State private var thumbnailItem: PhotosPickerItem?
    @State private var showQuizEditor = false
    @State private var showDeleteConfirmation = false
    let onDeleted: () -> Void

    init(video: Video, environment: AppEnvironment, onDeleted: @escaping () -> Void) {
        self.environment = environment
        self.onDeleted = onDeleted
        _viewModel = StateObject(wrappedValue: VideoSettingsViewModel(video: video, environment: environment))
    }

    var body: some View {
        Form {
            titleSection
            thumbnailSection
            quizSection
            shareSection
            if viewModel.canDownload {
                downloadSection
            }
            deleteSection
            messageSection
        }
        .navigationTitle("Lesson settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Strings.close) { dismiss() }
            }
        }
        .task { await viewModel.loadDownloadEntitlement() }
        .onChange(of: thumbnailItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                await viewModel.uploadThumbnail(data)
            }
        }
        .onChange(of: viewModel.deleted) { _, deleted in
            if deleted {
                onDeleted()
                dismiss()
            }
        }
        // Pushed, not sheeted — QuizBuilderView only has Save/Preview in its
        // own toolbar (no Cancel), since every existing call site pushes it
        // onto Creator mode's NavigationStack and relies on the system back
        // button. Sheeting it in a fresh NavigationStack here would leave no
        // way to back out without saving.
        .navigationDestination(isPresented: $showQuizEditor) {
            QuizBuilderView(video: viewModel.video, environment: environment, allowAIDraft: false)
        }
        .confirmationDialog(
            "Remove this lesson?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { Task { await viewModel.deleteVideo() } }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var titleSection: some View {
        Section("Title") {
            TextField("Title", text: $viewModel.title)
            Button("Save title") { Task { await viewModel.saveTitle() } }
                .disabled(viewModel.isSavingTitle || viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var thumbnailSection: some View {
        Section("Thumbnail") {
            if let urlString = viewModel.video.thumbnailURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(theme.surfaceSubtle)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .listRowInsets(EdgeInsets())
            }
            PhotosPicker(selection: $thumbnailItem, matching: .images) {
                HStack {
                    Label(viewModel.video.thumbnailURL == nil ? "Choose thumbnail" : "Replace thumbnail", systemImage: "photo")
                    if viewModel.isUploadingThumbnail {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isUploadingThumbnail)
        }
    }

    private var quizSection: some View {
        Section {
            Button("Edit quiz") { showQuizEditor = true }
                .disabled(!viewModel.video.hasQuiz)
            Button {
                Task { await viewModel.regenerateQuiz() }
            } label: {
                HStack {
                    Text("Regenerate quiz")
                    if viewModel.isRegeneratingQuiz {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isRegeneratingQuiz || !viewModel.video.hasQuiz)
        } header: {
            Text("Quiz")
        } footer: {
            Text("Regenerating writes a whole new quiz from this lesson's script — up to 3 times a day per lesson, resetting at midnight UTC.")
        }
    }

    private var shareSection: some View {
        Section {
            Button {
                Task { await viewModel.toggleShare() }
            } label: {
                HStack {
                    Text(viewModel.isShared ? "Make private" : "Share to Social")
                    if viewModel.isTogglingShare {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isTogglingShare || !viewModel.canToggleShare)
        } footer: {
            if !viewModel.canToggleShare {
                Text(viewModel.video.status == .ready ? "Lessons from the developer API can't be shared to Social." : "Finish generating before this can be shared.")
            }
        }
    }

    private var downloadSection: some View {
        Section {
            Button {
                Task { await viewModel.downloadToPhotos() }
            } label: {
                HStack {
                    Label("Download to Photos", systemImage: "square.and.arrow.down")
                    if viewModel.isDownloading {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isDownloading || viewModel.video.status != .ready)
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Remove video", role: .destructive) { showDeleteConfirmation = true }
                .disabled(viewModel.isDeleting)
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if let error = viewModel.errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(theme.error)
            }
        } else if let success = viewModel.successMessage {
            Section {
                Label(success, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(theme.success)
            }
        }
    }
}
