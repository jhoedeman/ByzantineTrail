import CloudKit

/// Live public-database backend for site suggestions (M5c). Writes a create-only
/// `SiteSuggestion` record the owner reads via the CloudKit Dashboard. No
/// submitter identity is stored (random UUID recordName; no userRecordID fetch).
/// All CloudKit is confined to this file. Activated by the owner (CLOUDKIT_SETUP.md).
final class CloudKitSuggestionService: SuggestionSubmitting {
    private let db: CKDatabase

    init(containerID: String = "iCloud.com.byzantinetrail.app") {
        db = CKContainer(identifier: containerID).publicCloudDatabase
    }

    func submit(_ suggestion: SiteSuggestion) async throws {
        let rec = CKRecord(recordType: "SiteSuggestion") // random UUID recordName
        rec["name"] = suggestion.name as CKRecordValue
        if let v = suggestion.location   { rec["location"]   = v as CKRecordValue }
        if let v = suggestion.whyInclude { rec["whyInclude"] = v as CKRecordValue }
        if let v = suggestion.linksText  { rec["linksText"]  = v as CKRecordValue }
        rec["submittedAt"] = Date() as CKRecordValue
        _ = try await db.save(rec)
    }
}
