import Combine
import Foundation

/// Lets the user pick the UI language independently of the phone's system
/// language setting — important since many learners haven't configured
/// their iPhone in English yet. Uses the classic "bundle swizzle" trick:
/// look strings up in a specific `.lproj` bundle instead of relying on
/// `NSLocalizedString`'s automatic system-locale resolution.
///
/// Note: this governs UI chrome only. Civics **questions** and quiz answers
/// are always shown in English regardless of this setting, and
/// **explanations** are always shown in Vietnamese — those are fixed
/// per-field choices in the content model, not affected by this manager.
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let storageKey = "app_ui_language"

    @Published private(set) var currentLanguage: AppLanguage
    private var bundle: Bundle

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey).flatMap(AppLanguage.init(rawValue:))
        let initial = stored ?? .vietnamese
        currentLanguage = initial
        bundle = Self.bundle(for: initial)
    }

    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        bundle = Self.bundle(for: language)
        UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
    }

    func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let languageBundle = Bundle(path: path)
        else { return .main }
        return languageBundle
    }
}

extension String {
    /// Looks up `self` as a key in the currently selected UI language bundle.
    /// Read `LocalizationManager`'s doc comment for what this does and does
    /// not cover.
    var localized: String { LocalizationManager.shared.string(self) }
}
