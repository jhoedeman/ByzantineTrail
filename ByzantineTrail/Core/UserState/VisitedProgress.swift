import Foundation

/// One progress row: how many sites in a bucket are visited.
struct ProgressBucket: Identifiable, Equatable {
    let id: String        // stable key (country code or tier rawValue)
    let label: String     // display label
    let visited: Int
    let total: Int
    var fraction: Double { total == 0 ? 0 : Double(visited) / Double(total) }
}

/// Pure visited-progress computation for the Profile screen: overall plus
/// per-country and per-tier breakdowns, from the visited id set + catalog.
struct VisitedProgress: Equatable {
    let visited: Int
    let total: Int
    let byCountry: [ProgressBucket]
    let byTier: [ProgressBucket]

    var fraction: Double { total == 0 ? 0 : Double(visited) / Double(total) }

    static func compute(visited visitedIDs: Set<String>, sites: [Site]) -> VisitedProgress {
        let visitedCount = sites.reduce(into: 0) { $0 += visitedIDs.contains($1.id) ? 1 : 0 }

        // Per country, sorted by localized country name.
        var countryTotals: [String: (visited: Int, total: Int)] = [:]
        for site in sites {
            var e = countryTotals[site.country] ?? (0, 0)
            e.total += 1
            if visitedIDs.contains(site.id) { e.visited += 1 }
            countryTotals[site.country] = e
        }
        let byCountry = countryTotals
            .map { ProgressBucket(id: $0.key, label: CountryName.localized($0.key),
                                  visited: $0.value.visited, total: $0.value.total) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        // Per tier, fixed major → notable → minor order.
        let byTier: [ProgressBucket] = Importance.allCases.map { imp in
            let inTier = sites.filter { $0.importance == imp }
            let v = inTier.reduce(into: 0) { $0 += visitedIDs.contains($1.id) ? 1 : 0 }
            return ProgressBucket(id: imp.rawValue, label: imp.displayLabel,
                                  visited: v, total: inTier.count)
        }

        return VisitedProgress(visited: visitedCount, total: sites.count,
                               byCountry: byCountry, byTier: byTier)
    }
}
