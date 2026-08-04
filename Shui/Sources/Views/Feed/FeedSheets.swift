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
