import Testing

struct SanityTests {
    @Test func testTargetRuns() {
        #expect(1 + 1 == 2)
    }
}
