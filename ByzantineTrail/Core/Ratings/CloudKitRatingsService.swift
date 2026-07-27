import CloudKit

/// Real public-database ratings backend (spec §0.2, §4). `Rating` records are the
/// source of truth; `RatingSummary` is a delta-maintained, recomputable cache.
/// All CloudKit is confined to this file. Activated by the owner (CLOUDKIT_SETUP.md).
final class CloudKitRatingsService: RatingsServicing {
    private let db: CKDatabase
    private let container: CKContainer

    init(containerID: String = "iCloud.com.byzantinetrail.app") {
        container = CKContainer(identifier: containerID)
        db = container.publicCloudDatabase
    }

    private func summaryRecordID(_ siteId: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "summary-\(siteId)")
    }
    private func ratingRecordID(_ siteId: String, _ user: CKRecord.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(siteId)|\(user.recordName)")
    }

    private func summary(from record: CKRecord?, siteId: String) -> RatingSummary {
        RatingSummary(siteId: siteId,
                      count: (record?["count"] as? Int) ?? 0,
                      total: (record?["total"] as? Int) ?? 0)
    }

    // MARK: RatingsServicing

    func load(for siteId: String) async throws -> SiteRatingState {
        let userID = try await container.userRecordID()
        async let summaryRec = try? db.record(for: summaryRecordID(siteId))
        async let mineRec = try? db.record(for: ratingRecordID(siteId, userID))
        let cached = summary(from: await summaryRec, siteId: siteId)
        let mine = (await mineRec)?["value"] as? Int
        // Reconcile: recompute from the actual Rating records; overwrite on drift.
        let reconciled = try await reconcile(siteId: siteId, cached: cached)
        return SiteRatingState(summary: reconciled.count == 0 ? nil : reconciled, mine: mine)
    }

    func allSummaries() async throws -> [String: RatingSummary] {
        let query = CKQuery(recordType: "RatingSummary", predicate: NSPredicate(value: true))
        let (results, _) = try await db.records(matching: query)
        var out: [String: RatingSummary] = [:]
        for (_, result) in results {
            if let rec = try? result.get(), let siteId = rec["siteId"] as? String {
                out[siteId] = summary(from: rec, siteId: siteId)
            }
        }
        return out
    }

    func submit(rating: Int, for siteId: String) async throws -> RatingSummary {
        let userID = try await container.userRecordID()
        let ratingID = ratingRecordID(siteId, userID)
        let old = (try? await db.record(for: ratingID))?["value"] as? Int
        let ratingRec = CKRecord(recordType: "Rating", recordID: ratingID)
        ratingRec["siteId"] = siteId as CKRecordValue
        ratingRec["value"] = rating as CKRecordValue
        _ = try await db.save(ratingRec)
        return try await updateSummary(siteId: siteId, old: old, new: rating)
    }

    func removeRating(for siteId: String) async throws -> RatingSummary {
        let userID = try await container.userRecordID()
        let ratingID = ratingRecordID(siteId, userID)
        let old = (try? await db.record(for: ratingID))?["value"] as? Int
        if old != nil { _ = try? await db.deleteRecord(withID: ratingID) }
        return try await updateSummary(siteId: siteId, old: old, new: nil)
    }

    // MARK: Summary maintenance (delta fast-path + change-tag retry + recompute)

    private func updateSummary(siteId: String, old: Int?, new: Int?) async throws -> RatingSummary {
        for _ in 0..<3 {
            let existing = try? await db.record(for: summaryRecordID(siteId))
            let current = summary(from: existing, siteId: siteId)
            let next = RatingMath.applyDelta(to: current, old: old, new: new)
            let rec = existing ?? CKRecord(recordType: "RatingSummary", recordID: summaryRecordID(siteId))
            rec["siteId"] = siteId as CKRecordValue
            rec["count"] = next.count as CKRecordValue
            rec["total"] = next.total as CKRecordValue
            do { _ = try await db.save(rec); return next }
            catch let error as CKError where error.code == .serverRecordChanged { continue }
        }
        // Retry exhausted → authoritative recompute from Rating records.
        return try await reconcile(siteId: siteId, cached: summary(from: nil, siteId: siteId), force: true)
    }

    /// Recompute the summary from the actual Rating records and overwrite the cache
    /// when it has drifted (self-heal, spec §0.2). Returns the trustworthy summary.
    private func reconcile(siteId: String, cached: RatingSummary, force: Bool = false) async throws -> RatingSummary {
        let query = CKQuery(recordType: "Rating",
                            predicate: NSPredicate(format: "siteId == %@", siteId))
        let (results, _) = try await db.records(matching: query)
        let values = results.compactMap { try? $0.1.get()["value"] as? Int }.compactMap { $0 }
        let recomputed = RatingMath.recompute(siteId: siteId, values: values)
        if force || RatingMath.needsReconcile(cached: cached, recomputed: recomputed) {
            let rec = (try? await db.record(for: summaryRecordID(siteId)))
                ?? CKRecord(recordType: "RatingSummary", recordID: summaryRecordID(siteId))
            rec["siteId"] = siteId as CKRecordValue
            rec["count"] = recomputed.count as CKRecordValue
            rec["total"] = recomputed.total as CKRecordValue
            _ = try? await db.save(rec)
        }
        return recomputed
    }
}
