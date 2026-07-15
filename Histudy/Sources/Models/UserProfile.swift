import Foundation
import SwiftData

/// The single local user profile. This is a study aid, not an account
/// system — everything lives on-device (SwiftData / local SQLite store),
/// there is no server-side user database in the MVP.
@Model
final class UserProfile {
    var id: UUID
    var displayName: String
    var uiLanguageRaw: String
    var createdAt: Date
    var currentStreak: Int
    var longestStreak: Int
    var lastSessionDate: Date?
    var totalLessonsCompleted: Int
    var totalQuizzesTaken: Int
    var dailyGoalMinutes: Int
    var hasCompletedOnboarding: Bool

    // Freemium/account state. Declared with defaults so SwiftData can
    // lightweight-migrate stores created before these fields existed.
    var subscriptionTierRaw: String = SubscriptionTier.free.rawValue
    var authProviderRaw: String?
    var isSignedIn: Bool = false
    /// Lessons completed in the feed, driving the "sign in after two
    /// lessons" prompt.
    var feedLessonsCompleted: Int = 0

    /// Encoded `LocalOfficialsProfile` (state, Senators, Representative,
    /// Governor) — stored as JSON since SwiftData models can't easily embed
    /// arbitrary Codable structs as first-class relationships for a value type.
    var localOfficialsData: Data?

    init(
        id: UUID = UUID(),
        displayName: String = "",
        uiLanguage: AppLanguage = .vietnamese,
        createdAt: Date = Date(),
        dailyGoalMinutes: Int = 7
    ) {
        self.id = id
        self.displayName = displayName
        self.uiLanguageRaw = uiLanguage.rawValue
        self.createdAt = createdAt
        self.currentStreak = 0
        self.longestStreak = 0
        self.lastSessionDate = nil
        self.totalLessonsCompleted = 0
        self.totalQuizzesTaken = 0
        self.dailyGoalMinutes = dailyGoalMinutes
        self.hasCompletedOnboarding = false
        self.localOfficialsData = nil
    }

    var uiLanguage: AppLanguage {
        get { AppLanguage(rawValue: uiLanguageRaw) ?? .vietnamese }
        set { uiLanguageRaw = newValue.rawValue }
    }

    var subscriptionTier: SubscriptionTier {
        get { SubscriptionTier(rawValue: subscriptionTierRaw) ?? .free }
        set { subscriptionTierRaw = newValue.rawValue }
    }

    var authProvider: AuthProvider? {
        get { authProviderRaw.flatMap(AuthProvider.init(rawValue:)) }
        set { authProviderRaw = newValue?.rawValue }
    }

    var isPro: Bool { subscriptionTier == .pro }

    var localOfficials: LocalOfficialsProfile {
        get {
            guard let localOfficialsData,
                  let decoded = try? JSONDecoder().decode(LocalOfficialsProfile.self, from: localOfficialsData)
            else { return LocalOfficialsProfile() }
            return decoded
        }
        set {
            localOfficialsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Call once per day the user opens a session; updates the streak and
    /// resets it if a day was missed.
    func registerSessionDay(now: Date = Date()) {
        let calendar = Calendar.current
        defer { lastSessionDate = now }

        guard let lastSessionDate else {
            currentStreak = 1
            longestStreak = max(longestStreak, currentStreak)
            return
        }

        if calendar.isDate(lastSessionDate, inSameDayAs: now) {
            return // already counted today
        }

        let daysBetween = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastSessionDate), to: calendar.startOfDay(for: now)).day ?? 0
        if daysBetween == 1 {
            currentStreak += 1
        } else {
            currentStreak = 1
        }
        longestStreak = max(longestStreak, currentStreak)
    }
}
