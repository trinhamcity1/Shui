import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The flow that has to feel effortless, because it's the one you'll run
/// hundreds of times (prompts/phase-05-creator-mode.md §4). One screen that
/// changes shape as the upload progresses, rather than a wizard — the
/// creator can see the trim, the thumbnail, and the metadata at once and go
/// back to any of them until they tap Upload.
struct VideoUploadFlowView: View {
    let environment: AppEnvironment
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: VideoUploadViewModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFileImporter = false

    init(topic: Topic, environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: VideoUploadViewModel(topic: topic, environment: environment))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch viewModel.stage {
                case .picking:
                    pickSection
                case .inspecting:
                    Section { ProgressView("Reading video…") }
                case .ready, .exporting:
                    previewSection
                    trimSection
                    thumbnailSection
                    metadataSection
                    actionSection
                case .uploading, .finalizing:
                    progressSection
                case .done:
                    doneSection
                case .failed(let message, let canRetry):
                    failureSection(message: message, canRetry: canRetry)
                }
            }
            .navigationTitle("Upload video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) {
                        Task {
                            await viewModel.cancelPendingUpload()
                            dismiss()
                        }
                    }
                    .disabled(viewModel.stage.isBusy)
                }
            }
            .interactiveDismissDisabled(viewModel.stage.isBusy)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
            .onChange(of: viewModel.thumbnailSeconds) { _, _ in
                Task { await viewModel.refreshThumbnail() }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie],
                allowsMultipleSelection: false
            ) { result in
                Task { await load(fileImportResult: result) }
            }
        }
    }

    // MARK: - Sections

    private var pickSection: some View {
        Section {
            PhotosPicker(selection: $pickerItem, matching: .videos) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("Choose from Files", systemImage: "folder")
            }
        } footer: {
            Text("Vertical videos under 10 minutes work best — the feed is built for portrait. Longer or landscape videos still upload, with a warning.")
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let inspection = viewModel.inspection {
            Section("Source") {
                LabeledContent("Length", value: format(inspection.duration))
                LabeledContent("Size", value: VideoExporter.formattedSize(inspection.sizeBytes))
                LabeledContent("Dimensions", value: "\(Int(inspection.naturalSize.width))×\(Int(inspection.naturalSize.height))")
                ForEach(inspection.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(theme.warning)
                }
            }
        }
    }

    @ViewBuilder
    private var trimSection: some View {
        if let inspection = viewModel.inspection, inspection.duration > 0 {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start: \(format(viewModel.trimStart))")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                    Slider(value: $viewModel.trimStart, in: 0...max(0.1, viewModel.trimEnd))
                    Text("End: \(format(viewModel.trimEnd))")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                    Slider(value: $viewModel.trimEnd, in: min(viewModel.trimStart + 0.1, inspection.duration)...inspection.duration)
                }
            } header: {
                Text("Trim")
            } footer: {
                Text("Keeping \(format(viewModel.trimmedDuration)) of \(format(inspection.duration)).")
            }
        }
    }

    @ViewBuilder
    private var thumbnailSection: some View {
        if let inspection = viewModel.inspection {
            Section {
                if let thumbnail = viewModel.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .frame(maxWidth: .infinity)
                }
                Slider(value: $viewModel.thumbnailSeconds, in: 0...max(0.1, inspection.duration))
            } header: {
                Text("Thumbnail")
            } footer: {
                Text("Scrub to pick the frame learners see first.")
            }
        }
    }

    private var metadataSection: some View {
        Section("Details") {
            TextField("Title", text: $viewModel.title)
            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.caption).foregroundStyle(theme.textSecondary)
                TextEditor(text: $viewModel.videoDescription).frame(minHeight: 60).font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcript (optional)").font(.caption).foregroundStyle(theme.textSecondary)
                TextEditor(text: $viewModel.transcript).frame(minHeight: 80).font(.subheadline)
                Text("A transcript makes the AI tutor markedly better and lets it draft quiz questions for you.")
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            if case .exporting(let progress) = viewModel.stage {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                    Text("Compressing… \(Int(progress * 100))%")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                }
            } else if viewModel.exportedURL == nil {
                Button("Compress for upload") {
                    Task { await viewModel.prepareForUpload() }
                }
            } else {
                LabeledContent("Upload size", value: VideoExporter.formattedSize(viewModel.exportedSizeBytes))
                Button("Upload") {
                    Task { await viewModel.startUpload() }
                }
                .disabled(!viewModel.canStartUpload)
            }
        } footer: {
            if viewModel.exportedURL == nil {
                Text("Compressing to 1080p H.264 first keeps the upload small — the original is never sent as-is.")
            }
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        Section {
            switch viewModel.stage {
            case .uploading(let fraction, let sent, let total):
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: fraction)
                    Text("\(VideoExporter.formattedSize(Int(sent))) of \(VideoExporter.formattedSize(Int(total)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.textSecondary)
                }
            case .finalizing:
                ProgressView("Finishing up…")
            default:
                EmptyView()
            }
        } footer: {
            Text("Keep the app open until this finishes. If it's interrupted, the video shows as failed in the topic and you can upload it again.")
        }
    }

    private var doneSection: some View {
        Section {
            Label("Uploaded", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(theme.success)
            Text("This video needs a quiz before it can be published.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
            Button("Done") { dismiss() }
        }
    }

    private func failureSection(message: String, canRetry: Bool) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(theme.error)
            if canRetry {
                Button("Try again") {
                    Task { await viewModel.retryUpload() }
                }
            }
            Button(Strings.cancel, role: .cancel) {
                Task {
                    await viewModel.cancelPendingUpload()
                    dismiss()
                }
            }
        }
    }

    // MARK: - Helpers

    /// `PhotosPickerItem` hands back bytes, not a stable file URL, so the
    /// movie is written to a temp file first — `AVURLAsset` and the upload
    /// task both need something on disk.
    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        do {
            try data.write(to: url)
            await viewModel.accept(pickedURL: url)
        } catch {
            // Falls through to the picker still being shown, which is the
            // honest state — nothing was loaded.
        }
    }

    /// Files/iCloud Drive hands back a security-scoped URL that's only
    /// guaranteed valid for the duration of this access — `AVURLAsset` and
    /// the later export/upload steps run well past that, so the file is
    /// copied into our own temp directory immediately, same as the Photos
    /// path already does for its own reason (a stable, owned URL).
    private func load(fileImportResult: Result<[URL], Error>) async {
        guard case .success(let urls) = fileImportResult, let sourceURL = urls.first else { return }
        guard sourceURL.startAccessingSecurityScopedResource() else { return }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: localURL)
            await viewModel.accept(pickedURL: localURL)
        } catch {
            // Falls through to the picker still being shown — nothing was
            // loaded, which is the honest state.
        }
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
