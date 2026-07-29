import Combine
import Foundation

struct CategoryMasterySummary: Identifiable {
    let id: QuestionCategory
    let info: CategoryInfo?
    let total: Int
    let mastered: Int
    let learning: Int
    let new: Int
    /// Answer accuracy across studied questions in this category, 0...1,
    /// or nil when nothing has been answered yet. Drives the pro-tier
    /// analytics section.
    let accuracy: Double?

    var accuracyLabel: String {
        guard let accuracy else { return "—" }
        return "\(Int((accuracy * 100).rounded()))%"
    }
}

@MainActor
final class ProgressViewModel: ObservableObject {
    @Published private(set) var categorySummaries: [CategoryMasterySummary] = []
    @Published private(set) var overallMastered = 0
    @Published private(set) var overallLearning = 0
    @Published private(set) var overallNew = 0

    var overallTotal: Int { overallMastered + overallLearning + overallNew }

    func load() {
        let allProgress = PersistenceController.shared.allProgress()
        let progressByID = Dictionary(uniqueKeysWithValues: allProgress.map { ($0.questionId, $0) })
        let questions = ContentStore.shared.questions

        var mastered = 0
        var learning = 0
        var brandNew = 0
        var summaries: [CategoryMasterySummary] = []

        for category in QuestionCategory.allCases {
            let inCategory = questions.filter { $0.category == category }
            var catMastered = 0
            var catLearning = 0
            var catNew = 0
            var answeredCorrect = 0
            var answeredTotal = 0

            for question in inCategory {
                guard let progress = progressByID[question.id], !progress.isNew else {
                    catNew += 1
                    continue
                }
                if progress.masteryLevel >= 3 {
                    catMastered += 1
                } else {
                    catLearning += 1
                }
                answeredCorrect += progress.timesCorrect
                answeredTotal += progress.timesCorrect + progress.timesIncorrect
            }

            mastered += catMastered
            learning += catLearning
            brandNew += catNew
            summaries.append(CategoryMasterySummary(
                id: category,
                info: ContentStore.shared.categoryInfo(for: category),
                total: inCategory.count,
                mastered: catMastered,
                learning: catLearning,
                new: catNew,
                accuracy: answeredTotal > 0 ? Double(answeredCorrect) / Double(answeredTotal) : nil
            ))
        }

        categorySummaries = summaries.sorted { ($0.info?.sortOrder ?? 0) < ($1.info?.sortOrder ?? 0) }
        overallMastered = mastered
        overallLearning = learning
        overallNew = brandNew
    }
}
