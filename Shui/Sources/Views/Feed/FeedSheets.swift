import SwiftUI

/// The "more" affordance on a feed page's caption — full, untruncated
/// description plus topic context.
struct VideoInfoSheet: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(video.topicTitle)
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Text(video.title)
                        .font(.title2.bold())
                    if !video.description.isEmpty {
                        Text(video.description)
                            .font(.body)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("About this lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
        }
    }
}

/// A launchable stub, not a mockup — reused for the rail's Comments and AI
/// sheets, which are real screens in Phase 3 and Phase 4 respectively.
struct ComingSoonSheet: View {
    let title: String
    let phase: Int
    let detail: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("Coming in phase \(phase)")
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Stands in for real sign-in (Phase 3) wherever a guest hits a
/// signed-in-only action — liking, commenting, the AI tutor.
struct SignInStubSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.shell.gradientStart)
                Text("Sign in to continue")
                    .font(.title3.bold())
                Text("Liking, commenting, and the AI tutor need a real account. Sign-in lands in Phase 3.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(Strings.done) { dismiss() }
                    .buttonStyle(.shuiPill)
                    .padding(.top, 8)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .presentationDetents([.medium])
    }
}
