import SwiftUI

/// Shown whenever the feed has nothing to page through. Covers both edge
/// cases from the phase brief with one view: a fresh install with nothing
/// published yet, and a learner who's genuinely watched everything — the
/// composer always places a due-review item if one exists (see
/// `FeedComposer`), so an empty feed with a nonzero `dueReviewCount` can't
/// actually happen, but the copy still adapts in case that invariant ever
/// changes. Never a spinner forever, either way.
struct FeedEmptyStateView: View {
    let dueReviewCount: Int
    let onExplore: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: dueReviewCount > 0 ? "checkmark.seal" : "play.rectangle.on.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
            Text(dueReviewCount > 0 ? "You're all caught up" : "Nothing here yet")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Explore more topics", action: onExplore)
                .buttonStyle(.shuiPill)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var detail: String {
        if dueReviewCount > 0 {
            return "\(dueReviewCount) lesson\(dueReviewCount == 1 ? "" : "s") due for review."
        }
        return "Every video here is a short lesson that ends in a quiz. Once creators publish, they'll show up here."
    }
}
