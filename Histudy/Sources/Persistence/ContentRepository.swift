import Foundation

/// Generic loader for the bundled, hand-authored JSON content shipped inside
/// the app (see `scripts/generate_content.py` for how it's produced). Kept
/// separate from `ContentStore` so other lightweight lookups (like
/// `StateCapitalLookup`) can reuse the same decoding path.
enum ContentRepository {
    /// Anchors `Bundle(for:)` to wherever this module's own compiled code
    /// lives. `Bundle.main` alone isn't reliable here: when this code runs
    /// inside `HistudyTests`, `.main` resolves to the test runner, not the
    /// app bundle that actually has the JSON copied into it. Resolving via
    /// this marker class works whether the code is running as the real app
    /// or hosted inside a unit test target.
    private final class BundleMarker {}

    /// Tries an explicit override first (mainly for tests), then this
    /// module's own bundle, then `.main`, so content loads correctly from
    /// both the shipping app and the test target.
    static func loadJSON<T: Decodable>(_ resourceName: String, as type: T.Type, bundle: Bundle? = nil) -> T? {
        let candidates = [bundle, Bundle(for: BundleMarker.self), .main].compactMap { $0 }
        for candidate in candidates {
            guard let url = candidate.url(forResource: resourceName, withExtension: "json") else { continue }
            if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(T.self, from: data) {
                return decoded
            }
        }
        assertionFailure("Missing or invalid bundled resource \(resourceName).json — check Copy Bundle Resources.")
        return nil
    }
}
