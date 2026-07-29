import Testing
@testable import ByzantineTrail

struct AccountStatusPresentationTests {
    @Test func availableHasTitleAndNoExplainer() {
        let p = AccountStatusPresentation.make(for: .available)
        #expect(p.title == "Signed in to iCloud")
        #expect(p.explainer == nil)
        #expect(p.symbolName == "checkmark.icloud")
    }

    @Test func noAccountHasExplainer() {
        let p = AccountStatusPresentation.make(for: .noAccount)
        #expect(p.title == "Not signed in to iCloud")
        #expect(p.explainer != nil)
        #expect(p.symbolName == "xmark.icloud")
    }

    @Test func restrictedHasExplainer() {
        let p = AccountStatusPresentation.make(for: .restricted)
        #expect(p.title == "iCloud restricted")
        #expect(p.explainer != nil)
        #expect(p.symbolName == "exclamationmark.icloud")
    }

    @Test func unknownHasNoExplainer() {
        let p = AccountStatusPresentation.make(for: .unknown)
        #expect(p.title == "Checking iCloud status…")
        #expect(p.explainer == nil)
        #expect(p.symbolName == "icloud")
    }

    @Test func openSettingsHiddenOnlyWhenSignedIn() {
        #expect(AccountStatusPresentation.make(for: .available).showsOpenSettings == false)
        #expect(AccountStatusPresentation.make(for: .noAccount).showsOpenSettings == true)
        #expect(AccountStatusPresentation.make(for: .restricted).showsOpenSettings == true)
        #expect(AccountStatusPresentation.make(for: .unknown).showsOpenSettings == true)
    }
}
