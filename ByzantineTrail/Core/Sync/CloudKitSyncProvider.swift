import CloudKit

/// Real private-database sync backend (spec §7). Record type `UserSiteState`,
/// recordName == siteId, in the user's private DB. Sync scope is the three flags
/// only — `myRating` is never read or written here. All CloudKit is confined to
/// this file. Pull is query-by-`updatedAt` (no custom zone; fits the no-delete /
/// all-false model). Activated by the owner (docs/CLOUDKIT_SETUP.md).
final class CloudKitSyncProvider: RemoteSyncProvider {
    private let db: CKDatabase
    private static let recordType = "UserSiteState"

    init(containerID: String = "iCloud.com.byzantinetrail.app") {
        db = CKContainer(identifier: containerID).privateCloudDatabase
    }

    private func iso() -> ISO8601DateFormatter { ISO8601DateFormatter() }

    func push(_ changes: [UserSiteChange]) async throws {
        for change in changes {
            let id = CKRecord.ID(recordName: change.siteId)
            let rec = (try? await db.record(for: id))
                ?? CKRecord(recordType: Self.recordType, recordID: id)
            rec["isFavorite"] = (change.isFavorite ? 1 : 0) as CKRecordValue
            rec["wantsToVisit"] = (change.wantsToVisit ? 1 : 0) as CKRecordValue
            rec["visited"] = (change.visited ? 1 : 0) as CKRecordValue
            rec["updatedAt"] = change.updatedAt as CKRecordValue
            _ = try await db.save(rec)
        }
    }

    func pull(since token: SyncToken?) async throws -> (changes: [UserSiteChange], token: SyncToken) {
        let sinceDate = token.flatMap { iso().date(from: $0.raw) }
        let predicate: NSPredicate = sinceDate.map {
            NSPredicate(format: "updatedAt > %@", $0 as NSDate)
        } ?? NSPredicate(value: true)
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)

        var changes: [UserSiteChange] = []
        var maxDate = sinceDate ?? .distantPast
        for rec in try await allRecords(matching: query) {
            guard let updatedAt = rec["updatedAt"] as? Date else { continue }
            changes.append(UserSiteChange(
                siteId: rec.recordID.recordName,
                isFavorite: (rec["isFavorite"] as? Int ?? 0) != 0,
                wantsToVisit: (rec["wantsToVisit"] as? Int ?? 0) != 0,
                visited: (rec["visited"] as? Int ?? 0) != 0,
                myRating: nil, updatedAt: updatedAt))
            if updatedAt > maxDate { maxDate = updatedAt }
        }
        return (changes, SyncToken(raw: iso().string(from: maxDate)))
    }

    /// All records matching a query, following the cursor across every page.
    private func allRecords(matching query: CKQuery) async throws -> [CKRecord] {
        var out: [CKRecord] = []
        var response = try await db.records(matching: query)
        while true {
            for (_, result) in response.matchResults {
                if let rec = try? result.get() { out.append(rec) }
            }
            guard let cursor = response.queryCursor else { break }
            response = try await db.records(continuingMatchFrom: cursor)
        }
        return out
    }
}
