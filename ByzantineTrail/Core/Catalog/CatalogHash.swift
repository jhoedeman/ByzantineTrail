import Foundation
import CryptoKit

/// SHA-256 integrity check for downloaded catalog bytes (spec §3.2 step 4).
enum CatalogHash {
    /// Lowercase-hex SHA-256 digest of `data`.
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// True iff `data` hashes to `expectedHex` (case-insensitive comparison).
    static func verify(_ data: Data, matches expectedHex: String) -> Bool {
        sha256Hex(data).caseInsensitiveCompare(expectedHex) == .orderedSame
    }
}
