import SwiftUI

/// A topic's cover image, or the placeholder every card rendered inline
/// before cover images existed to show. One shared view rather than three
/// separate copies of the same `AsyncImage`/placeholder dance across
/// Explore, so a future change to the placeholder look only happens once.
///
/// Caller supplies the frame and clip shape — this view fills whatever
/// space it's given.
struct TopicCoverThumbnail: View {
    @Environment(\.theme) private var theme
    let urlString: String?
    var placeholderIcon: String = "play.rectangle.fill"
    var placeholderFont: Font = .body

    var body: some View {
        ZStack {
            theme.surfaceSubtle
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        Image(systemName: placeholderIcon)
            .font(placeholderFont)
            .foregroundStyle(theme.textTertiary)
    }
}
