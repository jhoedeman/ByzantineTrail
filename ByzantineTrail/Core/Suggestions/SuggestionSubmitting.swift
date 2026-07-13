struct SiteSuggestion: Equatable, Sendable {
    let name: String
    let location, whyInclude, linksText: String?
}

protocol SuggestionSubmitting: Sendable {
    func submit(_ suggestion: SiteSuggestion) async throws
}
