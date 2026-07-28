import Testing
@testable import ByzantineTrail

struct SuggestionValidatorTests {
    @Test func requiresNonEmptyName() {
        let r = SuggestionValidator.validate(name: "   ", location: "", whyInclude: "", linksText: "")
        #expect(r == .invalid([.nameRequired]))
    }

    @Test func trimsAndDropsEmptyOptionals() {
        let r = SuggestionValidator.validate(name: "  Hagia  ", location: " ",
                                             whyInclude: "", linksText: "  x ")
        #expect(r == .valid(SiteSuggestion(name: "Hagia", location: nil,
                                           whyInclude: nil, linksText: "x")))
    }

    @Test func nameAtCapPasses() {
        let ok = String(repeating: "a", count: 120)
        let r = SuggestionValidator.validate(name: ok, location: "", whyInclude: "", linksText: "")
        #expect(r == .valid(SiteSuggestion(name: ok, location: nil, whyInclude: nil, linksText: nil)))
    }

    @Test func nameOverCapFails() {
        let tooLong = String(repeating: "a", count: 121)
        #expect(SuggestionValidator.validate(name: tooLong, location: "", whyInclude: "", linksText: "")
            == .invalid([.tooLong(field: .name)]))
    }

    @Test func eachOptionalFieldCapEnforced() {
        #expect(SuggestionValidator.validate(name: "n", location: String(repeating: "b", count: 121),
                                             whyInclude: "", linksText: "")
            == .invalid([.tooLong(field: .location)]))
        #expect(SuggestionValidator.validate(name: "n", location: "",
                                             whyInclude: String(repeating: "c", count: 1001), linksText: "")
            == .invalid([.tooLong(field: .whyInclude)]))
        #expect(SuggestionValidator.validate(name: "n", location: "", whyInclude: "",
                                             linksText: String(repeating: "d", count: 501))
            == .invalid([.tooLong(field: .linksText)]))
    }
}
