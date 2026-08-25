import Testing
@testable import ByzantineTrail

struct DayClustererTests {
    private func site(_ id: String, _ lat: Double, _ lon: Double,
                      city: String?) -> PlannerSite {
        PlannerSite(id: id, name: id, coordinate: Coordinate(lat: lat, lon: lon),
                    cityId: city, type: .church, importance: .notable)
    }

    // MARK: grouping by city

    @Test func sitesSharingACityFormOneCluster() {
        let sites = [
            site("a", 41.89, 12.49, city: "rome"),
            site("b", 41.90, 12.45, city: "rome"),
            site("c", 41.88, 12.47, city: "rome"),
        ]
        let clusters = DayClusterer.cluster(sites)
        #expect(clusters.count == 1)
        #expect(clusters[0].cityId == "rome")
        #expect(clusters[0].sites.count == 3)
    }

    @Test func differentCitiesFormSeparateClusters() {
        let sites = [
            site("a", 41.89, 12.49, city: "rome"),
            site("b", 44.42, 12.20, city: "ravenna"),
            site("c", 41.00, 28.98, city: "istanbul"),
        ]
        #expect(DayClusterer.cluster(sites).count == 3)
    }

    @Test func clusterCentroidIsTheMeanOfItsSites() {
        let sites = [
            site("a", 40.0, 20.0, city: "x"),
            site("b", 42.0, 22.0, city: "x"),
        ]
        let centroid = DayClusterer.cluster(sites)[0].centroid
        #expect(abs(centroid.lat - 41.0) < 0.0001)
        #expect(abs(centroid.lon - 21.0) < 0.0001)
    }

    // MARK: sites with no city

    @Test func nearbyCitylessSiteJoinsTheClosestCluster() {
        let sites = [
            site("a", 41.890, 12.492, city: "rome"),
            site("b", 41.902, 12.454, city: "rome"),
            site("orphan", 41.895, 12.470, city: nil),   // ~1 km away
        ]
        let clusters = DayClusterer.cluster(sites)
        #expect(clusters.count == 1)
        #expect(clusters[0].sites.count == 3)
    }

    @Test func distantCitylessSiteBecomesItsOwnCluster() {
        let sites = [
            site("a", 41.890, 12.492, city: "rome"),
            site("far", 37.971, 23.727, city: nil),      // Athens
        ]
        let clusters = DayClusterer.cluster(sites)
        #expect(clusters.count == 2)
        #expect(clusters.contains { $0.cityId == nil && $0.sites.count == 1 })
    }

    @Test func citylessSitesNearEachOtherClusterTogether() {
        let sites = [
            site("p", 39.100, 21.500, city: nil),
            site("q", 39.104, 21.506, city: nil),        // ~0.7 km away
        ]
        let clusters = DayClusterer.cluster(sites)
        #expect(clusters.count == 1)
        #expect(clusters[0].sites.count == 2)
    }

    @Test func orphanThresholdIsFifteenKilometres() {
        #expect(DayClusterer.orphanThresholdMetres == 15_000.0)
    }

    // MARK: degenerate inputs

    @Test func emptyInputProducesNoClusters() {
        #expect(DayClusterer.cluster([]).isEmpty)
    }

    @Test func everySiteEndsUpInExactlyOneCluster() {
        let sites = [
            site("a", 41.89, 12.49, city: "rome"),
            site("b", 44.42, 12.20, city: "ravenna"),
            site("c", 41.00, 28.98, city: nil),
            site("d", 41.01, 28.99, city: nil),
        ]
        let placed = DayClusterer.cluster(sites).flatMap { $0.sites.map(\.id) }
        #expect(Set(placed) == ["a", "b", "c", "d"])
        #expect(placed.count == 4)
    }

    // MARK: ordering

    @Test func clustersAreOrderedIntoAShortChain() {
        // Ravenna, Rome, Athens fed out of geographic order.
        let sites = [
            site("athens", 37.97, 23.73, city: "athens"),
            site("rome", 41.89, 12.49, city: "rome"),
            site("ravenna", 44.42, 12.20, city: "ravenna"),
        ]
        let ordered = DayClusterer.order(DayClusterer.cluster(sites),
                                         mode: .driving, estimator: HaversineEstimator())
        let ids = ordered.map { $0.cityId }
        #expect(ids == ["ravenna", "rome", "athens"]
                || ids == ["athens", "rome", "ravenna"])
    }

    @Test func orderingASingleClusterIsIdentity() {
        let sites = [site("a", 41.89, 12.49, city: "rome")]
        let clusters = DayClusterer.cluster(sites)
        let ordered = DayClusterer.order(clusters, mode: .walking,
                                         estimator: HaversineEstimator())
        #expect(ordered.map(\.cityId) == ["rome"])
    }

    // MARK: merging adjacent cities

    /// Five Troodos villages, five distinct cityIds, all within a few km. These
    /// are one day's walk, not five days.
    @Test func adjacentVillagesShareAClusterRatherThanOneEach() {
        let sites = [
            site("kakopetria", 34.9880, 32.9000, city: "kakopetria"),
            site("galata",     34.9930, 32.9020, city: "galata"),
            site("moutoullas", 34.9930, 32.8340, city: "moutoullas"),
            site("kalopan",    34.9990, 32.8300, city: "kalopanayiotis"),
            site("pedoulas",   34.9720, 32.8300, city: "pedoulas"),
        ]
        let clusters = DayClusterer.cluster(sites)
        #expect(clusters.count == 1)
        #expect(clusters[0].sites.count == 5)
    }

    /// Three cityIds for one town, 140-270 m apart.
    @Test func oneTownWithSeveralCityIdsIsOneCluster() {
        let sites = [
            site("lower",  36.6870, 23.0530, city: "monemvasia"),
            site("upper",  36.6885, 23.0545, city: "monemvasia-upper-town"),
            site("both",   36.6878, 23.0538, city: "monemvasia-upper-and-lower-town"),
        ]
        #expect(DayClusterer.cluster(sites).count == 1)
    }

    /// Genuinely distant cities must still get their own clusters.
    @Test func distantCitiesAreNotMerged() {
        let sites = [
            site("r", 41.89, 12.49, city: "rome"),
            site("v", 44.42, 12.20, city: "ravenna"),
            site("i", 41.00, 28.98, city: "istanbul"),
            site("a", 37.97, 23.73, city: "athens"),
        ]
        #expect(DayClusterer.cluster(sites).count == 4)
    }
}
