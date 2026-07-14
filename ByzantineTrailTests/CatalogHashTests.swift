import Testing
import Foundation
@testable import ByzantineTrail

struct CatalogHashTests {
    // Known vector: SHA-256("abc") = ba7816bf...15ad
    private let abc = Data("abc".utf8)
    private let abcHex = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    @Test func computesKnownVector() {
        #expect(CatalogHash.sha256Hex(abc) == abcHex)
    }

    @Test func verifyMatches() {
        #expect(CatalogHash.verify(abc, matches: abcHex))
    }

    @Test func verifyIsCaseInsensitive() {
        #expect(CatalogHash.verify(abc, matches: abcHex.uppercased()))
    }

    @Test func verifyRejectsWrongDigest() {
        #expect(!CatalogHash.verify(abc, matches: "deadbeef"))
        #expect(!CatalogHash.verify(Data("abd".utf8), matches: abcHex))
    }
}
