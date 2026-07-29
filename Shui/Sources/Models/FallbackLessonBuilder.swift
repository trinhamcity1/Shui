import Foundation

/// Synthesizes a short flashcard-style lesson for any question that doesn't
/// yet have a hand-authored whiteboard-narrative script. This guarantees
/// every one of the 100 questions has a narrated lesson + quiz today, while
/// the flagship lessons (see `lessons.json`) get the richer treatment
/// described in the product brief. Expanding coverage post-MVP means adding
/// entries to `lessons.json` — this builder is the safety net, not the goal.
enum FallbackLessonBuilder {
    static func build(for question: CivicsQuestion) -> LessonScript {
        let categoryInfo = ContentStore.shared.categoryInfo(for: question.category)
        let titleEN = question.quickFactEN
        let titleVI = String(question.explanationVI.split(separator: ".").first ?? "")

        let narration: [NarrationBeat] = [
            NarrationBeat(id: "fb_n1", textEN: question.questionEN, textVI: question.questionEN, atSeconds: 0, durationSeconds: 4),
            NarrationBeat(id: "fb_n2", textEN: question.quickFactEN, textVI: question.explanationVI, atSeconds: 4, durationSeconds: 8),
        ]

        let actions: [SceneAction] = [
            SceneAction(id: "fb_a1", type: .titleCard, atSeconds: 0, durationSeconds: 4,
                        textEN: question.questionEN, textVI: question.questionEN,
                        symbol: categoryInfo?.sfSymbol ?? "book", region: nil, cityName: nil, year: nil, items: nil),
            SceneAction(id: "fb_a2", type: .bulletList, atSeconds: 4, durationSeconds: 8,
                        textEN: nil, textVI: nil, symbol: nil, region: nil, cityName: nil, year: nil,
                        items: [SceneListItem(textEN: question.quickFactEN, textVI: question.explanationVI)]),
        ]

        return LessonScript(
            id: "fallback_\(question.id)",
            questionIds: [question.id],
            titleEN: titleEN,
            titleVI: titleVI.isEmpty ? titleEN : titleVI,
            category: question.category,
            totalDurationSeconds: 12,
            narration: narration,
            actions: actions,
            style: .quickFact,
            videoURLString: nil,
            videoFileName: nil
        )
    }
}
