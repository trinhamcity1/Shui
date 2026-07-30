#if DEBUG
import AVKit
import SwiftUI
import UniformTypeIdentifiers

/// Exercises prompts/phase-01-backend.md §8.4 end-to-end: pick a local file,
/// createVideoUpload, PUT to R2, finalizeVideoUpload, confirm the video comes
/// back `status: .ready`, and play it from `playbackURL`. Phase 3 hasn't
/// built real auth yet, so sign-in goes through `DebugAuth` (Sources/Data) —
/// this view itself never imports Firebase.
///
/// Sign in with an account `bootstrap-admin.ts` has already granted
/// `creator` or `admin`, against a topic id that already exists (the seeded
/// civics topic id is `uscis-civics-2025`).
struct DebugUploadPipelineView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var email = ""
    @State private var password = ""
    @State private var topicID = "uscis-civics-2025"
    @State private var statusLines: [String] = []
    @State private var pickedFileURL: URL?
    @State private var readyVideo: Video?
    @State private var isBusy = false
    @State private var isPickerPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("1. Sign in as a creator/admin") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                    Button("Sign In") { Task { await signIn() } }
                        .disabled(email.isEmpty || password.isEmpty || isBusy)
                    Button("Create Account") { Task { await createAccount() } }
                        .disabled(email.isEmpty || password.isEmpty || isBusy)
                    Text("No signup screen exists yet (Phase 3). A new account starts as " +
                         "role \"learner\" — run bootstrap-admin.ts against this same " +
                         "project/emulator before it can call creator-only functions.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("2. Pick a local video and run the pipeline") {
                    TextField("Topic ID", text: $topicID)
                        .textInputAutocapitalization(.never)
                    Button("Choose File…") { isPickerPresented = true }
                    if let pickedFileURL {
                        Text(pickedFileURL.lastPathComponent).font(.caption)
                    }
                    Button("Run pick → upload → finalize → ready") {
                        Task { await runPipeline() }
                    }
                    .disabled(pickedFileURL == nil || isBusy)
                }

                if let readyVideo, let url = URL(string: readyVideo.playbackURL) {
                    Section("3. Play the result") {
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(height: 300)
                        Text("status: \(readyVideo.status.rawValue)")
                    }
                }

                Section("Log") {
                    ForEach(Array(statusLines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Debug: Upload Pipeline")
            .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.movie]) { result in
                if case .success(let url) = result {
                    pickedFileURL = url
                }
            }
        }
    }

    private func log(_ line: String) {
        statusLines.append(line)
    }

    private func signIn() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await DebugAuth.signIn(email: email, password: password)
            log("✅ Signed in as \(email)")
        } catch {
            log("❌ Sign-in failed: \(error.localizedDescription)")
        }
    }

    private func createAccount() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await DebugAuth.createAccount(email: email, password: password)
            log("✅ Created account \(email) — now run bootstrap-admin.ts, then Sign In")
        } catch {
            log("❌ Create account failed: \(error.localizedDescription)")
        }
    }

    private func runPipeline() async {
        guard let fileURL = pickedFileURL else { return }
        isBusy = true
        defer { isBusy = false }

        let needsSecurityScope = fileURL.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            let asset = AVURLAsset(url: fileURL)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            // Rough — ignores the track's preferredTransform, so a portrait
            // capture can report landscape sensor dimensions here. Fine for
            // smoke-testing the pipeline; not a stand-in for real metadata
            // extraction.
            let naturalSize = try await tracks.first?.load(.naturalSize) ?? CGSize(width: 1080, height: 1920)
            let aspectRatio = Double(naturalSize.width / max(naturalSize.height, 1))
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let sizeBytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0

            log("Requesting upload URL…")
            let ticket = try await environment.uploads.createVideoUpload(
                topicId: topicID,
                title: "Debug upload \(Date().formatted(date: .omitted, time: .standard))",
                description: nil,
                sizeBytes: sizeBytes,
                durationSeconds: duration,
                aspectRatio: aspectRatio,
                contentType: "video/mp4"
            )
            log("✅ Got videoId \(ticket.videoId)")

            log("Uploading to R2…")
            try await environment.uploads.uploadFile(fileURL, to: ticket.uploadURL, contentType: "video/mp4")
            log("✅ Uploaded")

            log("Finalizing…")
            try await environment.uploads.finalize(videoId: ticket.videoId, thumbnailR2Key: nil, transcript: nil)

            guard let video = try await environment.videos.video(id: ticket.videoId) else {
                log("❌ Video document not found after finalize")
                return
            }
            log("✅ status = \(video.status.rawValue), playbackURL = \(video.playbackURL)")
            readyVideo = video
        } catch {
            log("❌ Pipeline failed: \(error.localizedDescription)")
        }
    }
}
#endif
