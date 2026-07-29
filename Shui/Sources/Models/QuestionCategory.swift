import SwiftUI

/// Mirrors the official USCIS grouping of the 100 civics questions.
enum QuestionCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case govPrinciples = "gov_principles"
    case govSystem = "gov_system"
    case govRights = "gov_rights"
    case historyColonial = "history_colonial"
    case history1800s = "history_1800s"
    case historyRecent = "history_recent"
    case geography = "geography"
    case symbols = "symbols"
    case holidays = "holidays"

    var id: String { rawValue }
}

/// Localized display metadata for a category, loaded from `categories.json`
/// rather than hard-coded, so copy can be tuned without touching Swift code.
struct CategoryInfo: Codable, Identifiable {
    let id: String
    let nameEN: String
    let nameVI: String
    let sfSymbol: String
    let sortOrder: Int

    var category: QuestionCategory { QuestionCategory(rawValue: id) ?? .govPrinciples }
}
