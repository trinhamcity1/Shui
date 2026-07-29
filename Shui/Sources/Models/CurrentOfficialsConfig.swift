import Foundation

/// Time-sensitive answers, loaded from bundled `current_officials.json`
/// rather than hard-coded in Swift, so they can be corrected or refreshed
/// (e.g. via a content update bundled in an app update) without touching
/// the question bank or shipping a guess that will go stale.
struct CurrentOfficialsConfig: Codable {
    let lastUpdated: String
    let needsReviewAfterDays: Int
    let president: String
    let vicePresident: String
    let speakerOfHouse: String
    let chiefJustice: String
    let presidentParty: String
    let sourceNote: String

    func value(forRole role: String) -> String {
        switch role {
        case "president": return president
        case "vicePresident": return vicePresident
        case "speakerOfHouse": return speakerOfHouse
        case "chiefJustice": return chiefJustice
        case "presidentParty": return presidentParty
        default: return ""
        }
    }

    /// True once the bundled data is older than its review window, so the UI
    /// can surface a "please verify" banner instead of silently showing
    /// possibly-stale information.
    var isStale: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let updated = formatter.date(from: lastUpdated) else { return true }
        let days = Calendar.current.dateComponents([.day], from: updated, to: Date()).day ?? 0
        return days > needsReviewAfterDays
    }
}

/// User-specific answers the applicant (or their preparer) fills in once
/// during onboarding for questions that depend on where they live: their own
/// U.S. Senators, Representative, and Governor. These can't be bundled with
/// the app since they vary by state and change with elections.
struct LocalOfficialsProfile: Codable, Hashable {
    var stateName: String?
    var senator1: String?
    var senator2: String?
    var representative: String?
    var governor: String?

    var stateCapital: String? {
        guard let stateName else { return nil }
        return StateCapitalLookup.shared.capital(forState: stateName)
    }
}

/// Static per-state facts. State capitals do not change, so this is safe to
/// bundle directly (unlike officeholders, which do change).
final class StateCapitalLookup {
    static let shared = StateCapitalLookup()

    private let capitals: [String: String]

    private init() {
        capitals = ContentRepository.loadJSON("state_capitals", as: [String: String].self) ?? [:]
    }

    func capital(forState state: String) -> String? {
        capitals[state]
    }

    var allStateNames: [String] {
        capitals.keys.sorted()
    }
}
