import SwiftUI

/// Sheet listing a lesson's narration beats so the learner can jump
/// straight to a specific part instead of only watching linearly —
/// the "select what part of the lesson" option from the tutor's menu.
struct ChapterPickerView: View {
    let narration: [NarrationBeat]
    let language: AppLanguage
    let onSelect: (NarrationBeat) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(narration) { beat in
                Button {
                    onSelect(beat)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(beat.text(for: language))
                            .foregroundStyle(Theme.shell.ink)
                            .lineLimit(2)
                        Text(timeLabel(beat.atSeconds))
                            .font(.caption)
                            .foregroundStyle(Theme.shell.metadata)
                    }
                }
            }
            .navigationTitle(L10n.lessonChapterPickerTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
