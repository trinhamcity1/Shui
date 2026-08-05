import Foundation

/// The one tokenizer both sides of search go through — a stored topic's
/// indexed keywords, and a learner's typed query. Firestore has no native
/// full-text search (no tokenization, no "contains", no relevance scoring),
/// so this is the standard workaround: flatten searchable text into a plain
/// array of lowercase whole words, matched with `arrayContainsAny`. Sharing
/// one function for both sides is what actually matters here — if the
/// stored index and the query were tokenized differently, matches would
/// silently miss cases no test would catch until someone typed the "wrong"
/// word.
///
/// Deliberately whole-word, not sub-word/n-gram: "heal" won't match a
/// "healing" keyword. That's a real, known limitation, not an oversight —
/// true substring/fuzzy matching needs a real search index (Algolia,
/// Typesense, ...), which is its own, later piece of work. This solves
/// exactly what was asked: "healing", "life", "fullest" as complete,
/// independently searchable words across a topic's title, subtitle,
/// description, and tags.
enum SearchKeywords {
    /// Kept small on purpose: long enough to be a real word, short enough
    /// that this doesn't silently drop something someone actually typed.
    private static let minimumLength = 2
    /// Caps the stored array so one pathologically long description can't
    /// blow up a topic's index size — 60 distinct words comfortably covers
    /// a title + subtitle + a genuinely long description + 8 tags.
    private static let maximumKeywords = 60

    /// For indexing a topic: every distinct word across every field that
    /// should be searchable.
    static func index(title: String, subtitle: String, description: String, tags: [String]) -> [String] {
        let combined = ([title, subtitle, description] + tags).joined(separator: " ")
        return tokenize(combined, limit: maximumKeywords)
    }

    /// For a learner's typed query: the same tokenizer, so "life live"
    /// becomes exactly the two keywords that would have been indexed had
    /// those words appeared in a topic's own text. Firestore's
    /// `arrayContainsAny` allows up to 30 values, far more than a real
    /// search box entry will ever produce.
    static func query(_ text: String) -> [String] {
        tokenize(text, limit: 30)
    }

    private static func tokenize(_ text: String, limit: Int) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= minimumLength }
        for word in words where !seen.contains(word) {
            seen.insert(word)
            ordered.append(word)
            if ordered.count == limit { break }
        }
        return ordered
    }
}
