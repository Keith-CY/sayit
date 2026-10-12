import Foundation

/// Helpers that keep user-facing copy grammatical and consistent.
/// Rules live in docs/design/DESIGN.md § Copy.
enum CopyFormat {
    /// "1 word", "2 words", "1,204 words".
    static func count(_ value: Int, _ singular: String, plural: String? = nil) -> String {
        let noun = value == 1 ? singular : (plural ?? singular + "s")
        return "\(value.formatted()) \(noun)"
    }

    /// "1 entry" / "3 entries" style nouns that don't take a plain "s".
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        self.count(value, singular, plural: plural)
    }

    /// Byte counts in the system style ("2.47 GB").
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
