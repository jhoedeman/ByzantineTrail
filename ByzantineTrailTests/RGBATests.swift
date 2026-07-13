import Testing
@testable import ByzantineTrail

struct RGBATests {
    @Test func parsesSixDigitHexWithHash() {
        let c = RGBA(hex: "#E0B022")
        #expect(c != nil)
        #expect(abs(c!.r - 224.0/255.0) < 0.001)
        #expect(abs(c!.g - 176.0/255.0) < 0.001)
        #expect(abs(c!.b - 34.0/255.0) < 0.001)
        #expect(c!.a == 1.0)
    }

    @Test func parsesWithoutHash() {
        #expect(RGBA(hex: "130F0B") != nil)
    }

    @Test func rejectsBadInput() {
        #expect(RGBA(hex: "xyz") == nil)
        #expect(RGBA(hex: "#12") == nil)
    }
}
