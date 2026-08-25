import Foundation

/// A geographically coherent group of sites — usually one city.
struct SiteCluster: Equatable, Sendable {
    let cityId: String?
    let sites: [PlannerSite]
    let centroid: Coordinate
}

/// Groups chosen sites into day-sized geographic clusters.
///
/// `cityId` does almost all the work: every catalog site carries one, and 281
/// cities are already assigned. Only sites without a city need distance-based
/// handling. Splitting a cluster across several days is a *time* question and
/// belongs to `ItineraryPlanner`, which knows the day window.
enum DayClusterer {
    /// A city-less site further than this from every cluster becomes its own.
    static let orphanThresholdMetres = 15_000.0

    static func cluster(_ sites: [PlannerSite]) -> [SiteCluster] {
        guard !sites.isEmpty else { return [] }

        // Stable city grouping: first appearance decides the order.
        var cityOrder: [String] = []
        var byCity: [String: [PlannerSite]] = [:]
        var cityless: [PlannerSite] = []

        for site in sites {
            guard let cityId = site.cityId else {
                cityless.append(site)
                continue
            }
            if byCity[cityId] == nil {
                byCity[cityId] = []
                cityOrder.append(cityId)
            }
            byCity[cityId]?.append(site)
        }

        var groups: [(cityId: String?, sites: [PlannerSite])] =
            cityOrder.map { (cityId: $0, sites: byCity[$0] ?? []) }

        // Each city-less site joins the nearest group within the threshold, or
        // starts a new one that later city-less sites can also join.
        for site in cityless {
            var bestIndex: Int?
            var bestDistance = orphanThresholdMetres
            for (index, group) in groups.enumerated() {
                let distance = GreatCircle.metres(from: site.coordinate,
                                                  to: centroid(of: group.sites))
                if distance <= bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
            if let index = bestIndex {
                groups[index].sites.append(site)
            } else {
                groups.append((cityId: nil, sites: [site]))
            }
        }

        return groups.map {
            SiteCluster(cityId: $0.cityId, sites: $0.sites,
                        centroid: centroid(of: $0.sites))
        }
    }

    /// Orders clusters into a short chain by their centroids.
    static func order(_ clusters: [SiteCluster],
                      mode: TravelMode,
                      estimator: any TravelEstimating) -> [SiteCluster] {
        guard clusters.count > 2 else { return clusters }
        let indices = StopSequencer.sequence(coordinates: clusters.map(\.centroid),
                                             mode: mode, estimator: estimator)
        return indices.map { clusters[$0] }
    }

    static func centroid(of sites: [PlannerSite]) -> Coordinate {
        guard !sites.isEmpty else { return Coordinate(lat: 0, lon: 0) }
        let count = Double(sites.count)
        let lat = sites.reduce(0.0) { $0 + $1.coordinate.lat } / count
        let lon = sites.reduce(0.0) { $0 + $1.coordinate.lon } / count
        return Coordinate(lat: lat, lon: lon)
    }
}
