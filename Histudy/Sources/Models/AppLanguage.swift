import Foundation

/// The app's two supported UI/explanation languages. Per product spec, this
/// is independent of the phone's system language: many users will want a
/// Vietnamese interface regardless of their iOS locale. Civics **questions**
/// and quiz answers are always presented in English — that never switches —
/// because the real USCIS interview is conducted in English.
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Hashable {
    case english = "en"
    case vietnamese = "vi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    var speechLocale: String {
        switch self {
        case .english: return "en-US"
        case .vietnamese: return "vi-VN"
        }
    }
}
