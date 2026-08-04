import SwiftUI

/// The feed's vertically-stacked action rail. Comments stays open to guests
/// (only its composer is gated, per Phase 3) — the AI tutor is gated here,
/// at the button itself, since a guest should never see it open at all
/// (Phase 4: "Guest tapping AI gets the sign-in sheet").
struct FeedRightRail: View {
    @ObservedObject var page: FeedPageViewModel
    let isGuest: Bool
    let onLike: () -> Void
    let onComments: () -> Void
    let onAITutor: () -> Void
    let onRequireSignIn: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            railButton(
                systemImage: page.isLiked ? "heart.fill" : "heart",
                tint: page.isLiked ? .red : .white,
                label: "\(page.likeCount)",
                accessibilityLabel: "Like",
                accessibilityValue: "\(page.likeCount) likes"
            ) {
                if isGuest {
                    onRequireSignIn()
                } else {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onLike()
                }
            }

            railButton(
                systemImage: "bubble.right.fill",
                tint: .white,
                label: "\(page.commentCount)",
                accessibilityLabel: "Comments",
                accessibilityValue: "\(page.commentCount) comments",
                action: onComments
            )

            railButton(
                systemImage: "sparkles",
                tint: .white,
                label: "AI",
                accessibilityLabel: "Ask the AI tutor",
                accessibilityValue: nil
            ) {
                if isGuest {
                    onRequireSignIn()
                } else {
                    onAITutor()
                }
            }

            ShareLink(item: deepLink(for: page.video)) {
                railButtonLabel(
                    systemImage: "arrowshape.turn.up.right.fill",
                    tint: .white,
                    label: "Share"
                )
            }
            .accessibilityLabel("Share")
        }
        .font(.system(size: 28))
        .frame(width: 44)
    }

    private func deepLink(for video: Video) -> URL {
        // Custom scheme only for now — a web fallback needs a real domain,
        // which doesn't exist yet; add it here once one does.
        URL(string: "shui://video/\(video.id ?? "")") ?? URL(string: "shui://video")!
    }

    @ViewBuilder
    private func railButton(
        systemImage: String,
        tint: Color,
        label: String,
        accessibilityLabel: String,
        accessibilityValue: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            railButtonLabel(systemImage: systemImage, tint: tint, label: label)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
    }

    private func railButtonLabel(systemImage: String, tint: Color, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .shadow(color: .black.opacity(0.3), radius: 2)
                .frame(minWidth: 44, minHeight: 44)
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2)
        }
    }
}
