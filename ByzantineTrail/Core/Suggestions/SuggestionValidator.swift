import Foundation

/// Pure validation for the Suggest-a-Site form (M5c). Trims input, enforces a
/// required name and per-field length caps, and produces a `SiteSuggestion`
/// (optional fields empty → nil). No I/O — unit-tested alone.
enum SuggestionValidator {
    enum Field: Equatable { case name, location, whyInclude, linksText }
    enum Problem: Equatable { case nameRequired, tooLong(field: Field) }

    /// A validated suggestion, or the problems that blocked it. (Not `Result`,
    /// whose `Failure` must be an `Error`; `[Problem]` is plain data.)
    enum Validated: Equatable {
        case valid(SiteSuggestion)
        case invalid([Problem])
    }

    static let maxName = 120
    static let maxLocation = 120
    static let maxWhyInclude = 1000
    static let maxLinksText = 500

    static func validate(name: String, location: String,
                         whyInclude: String, linksText: String) -> Validated {
        let n = trim(name), loc = trim(location), why = trim(whyInclude), links = trim(linksText)

        var problems: [Problem] = []
        if n.isEmpty { problems.append(.nameRequired) }
        if n.count > maxName { problems.append(.tooLong(field: .name)) }
        if loc.count > maxLocation { problems.append(.tooLong(field: .location)) }
        if why.count > maxWhyInclude { problems.append(.tooLong(field: .whyInclude)) }
        if links.count > maxLinksText { problems.append(.tooLong(field: .linksText)) }

        guard problems.isEmpty else { return .invalid(problems) }
        return .valid(SiteSuggestion(name: n, location: nilIfEmpty(loc),
                                     whyInclude: nilIfEmpty(why), linksText: nilIfEmpty(links)))
    }

    private static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func nilIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
}
