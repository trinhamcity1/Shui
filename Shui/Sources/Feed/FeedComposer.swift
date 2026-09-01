import Foundation

/// Where a feed item came from — tracked alongside the composed list purely
/// so the interleaving constraints (below) can be checked without re-deriving
/// it from the video itself.
enum FeedSource: Equatable {
    case dueForReview
    case continueTopic
    case newInInterests
    case everythingElse
}

struct FeedItem: Identifiable, Equatable {
    let video: Video
    let source: FeedSource

    var id: String { video.id ?? video.playbackURL ?? video.title }
}

/// Builds the Learn tab's ordering: reviews are prioritized but interleaved,
/// never dominating the session. A pure function — no repository calls, no
/// dates read internally (`dueForReview` is assumed pre-filtered/sorted by
/// the caller) — so it's exercised directly in `FeedComposerTests`.
enum FeedComposer {
    /// Never place more than this many review items back to back.
    static let maxConsecutiveReview = 3
    /// Review items may not exceed this fraction of any 10-item window.
    static let reviewWindowSize = 10
    static let maxReviewPerWindow = 4

    /// - Parameters:
    ///   - dueForReview: soonest-due first.
    ///   - continueTopic: unwatched videos from the most-recently-active
    ///     topic, in `order`.
    ///   - newInInterests: unwatched public videos in the learner's chosen
    ///     categories, newest first.
    ///   - everythingElse: everything else public, newest first.
    ///   - alreadyPlaced: ids already in the feed from earlier batches, so a
    ///     later batch's dedup and interleave-constraint checks account for
    ///     items placed before this call.
    static func compose(
        dueForReview: [Video],
        continueTopic: [Video],
        newInInterests: [Video],
        everythingElse: [Video],
        alreadyPlaced: [FeedItem] = []
    ) -> [FeedItem] {
        var seenIds = Set(alreadyPlaced.map(\.id))
        var recentSources = Array(alreadyPlaced.suffix(reviewWindowSize - 1).map(\.source))

        var reviewIdx = 0
        var continueIdx = 0
        var newIdx = 0
        var restIdx = 0

        var output: [FeedItem] = []

        func nextUnseen(_ bucket: [Video], _ idx: inout Int) -> Video? {
            while idx < bucket.count {
                let video = bucket[idx]
                idx += 1
                let id = video.id ?? video.playbackURL ?? video.title
                if !seenIds.contains(id) {
                    return video
                }
            }
            return nil
        }

        func canPlaceReview() -> Bool {
            if recentSources.suffix(maxConsecutiveReview).allSatisfy({ $0 == .dueForReview })
                && recentSources.count >= maxConsecutiveReview {
                return false
            }
            let windowReviewCount = recentSources.suffix(reviewWindowSize - 1).filter { $0 == .dueForReview }.count
            return windowReviewCount < maxReviewPerWindow
        }

        func place(_ video: Video, source: FeedSource) {
            let id = video.id ?? video.playbackURL ?? video.title
            seenIds.insert(id)
            output.append(FeedItem(video: video, source: source))
            recentSources.append(source)
            if recentSources.count > reviewWindowSize - 1 {
                recentSources.removeFirst(recentSources.count - (reviewWindowSize - 1))
            }
        }

        while true {
            if canPlaceReview(), let video = nextUnseen(dueForReview, &reviewIdx) {
                place(video, source: .dueForReview)
                continue
            }
            if let video = nextUnseen(continueTopic, &continueIdx) {
                place(video, source: .continueTopic)
                continue
            }
            if let video = nextUnseen(newInInterests, &newIdx) {
                place(video, source: .newInInterests)
                continue
            }
            if let video = nextUnseen(everythingElse, &restIdx) {
                place(video, source: .everythingElse)
                continue
            }
            // Nothing else left — place a review item even if it would
            // violate the spacing constraint. A crowded review run beats an
            // empty feed when there's genuinely nothing else to show.
            if let video = nextUnseen(dueForReview, &reviewIdx) {
                place(video, source: .dueForReview)
                continue
            }
            break
        }

        return output
    }
}
