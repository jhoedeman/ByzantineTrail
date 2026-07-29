import Testing
@testable import ByzantineTrail

struct AppVersionInfoTests {
    @Test func readsPresentKeys() {
        let info = AppVersionInfo.from([
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
        ])
        #expect(info.version == "1.0")
        #expect(info.build == "1")
        #expect(info.displayString == "1.0 (1)")
    }

    @Test func missingKeysFallBackToDash() {
        let info = AppVersionInfo.from(nil)
        #expect(info.version == "—")
        #expect(info.build == "—")
        #expect(info.displayString == "— (—)")
    }
}
