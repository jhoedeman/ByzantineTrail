import Foundation
import Testing
@testable import ByzantineTrail

struct ItineraryPlannerTests {
    private func site(_ id: String, _ lat: Double, _ lon: Double,
                      city: String?, _ type: SiteType = .church,
                      _ importance: Importance = .notable) -> PlannerSite {
        PlannerSite(id: id, name: id, coordinate: Coordinate(lat: lat, lon: lon),
                    cityId: city, type: type, importance: importance)
    }

    /// Seven real Rome sites, roughly the worked example in the spec.
    private var romeDay: [PlannerSite] {
        [
            site("trastevere", 41.8896, 12.4695, city: "rome", .church, .major),
            site("sabina", 41.8843, 12.4794, city: "rome", .church, .notable),
            site("arch", 41.8898, 12.4906, city: "rome", .triumphalArch, .minor),
            site("maxentius", 41.8925, 12.4880, city: "rome", .archaeologicalSite, .notable),
            site("phocas", 41.8925, 12.4853, city: "rome", .column, .minor),
            site("clemente", 41.8894, 12.4977, city: "rome", .church, .major),
            site("prassede", 41.8959, 12.4981, city: "rome", .church, .notable),
        ]
    }

    // MARK: shape

    @Test func aSingleCityTripProducesOneDay() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1))
        #expect(trip.days.count == 1)
        #expect(trip.days[0].stops.count == 7)
        #expect(trip.unplacedSiteIds.isEmpty)
    }

    @Test func everyChosenSiteAppearsExactlyOnce() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 2))
        let ids = trip.days.flatMap { $0.stops.map(\.site.id) }
        #expect(Set(ids) == Set(romeDay.map(\.id)))
        #expect(ids.count == romeDay.count)
    }

    @Test func dwellTimesComeFromVisitDuration() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1))
        let byId = Dictionary(uniqueKeysWithValues:
            trip.days[0].stops.map { ($0.site.id, $0.dwellMinutes) })
        #expect(byId["trastevere"] == 75)   // major church
        #expect(byId["sabina"] == 30)       // notable church
        #expect(byId["arch"] == 15)         // minor arch, capped
        #expect(byId["maxentius"] == 45)    // notable archaeological, x1.5
        #expect(byId["phocas"] == 15)       // minor column, capped
    }

    @Test func paceFlowsThroughToDwellTimes() {
        let relaxed = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, pace: .relaxed, dayCount: 1))
        let packed = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, pace: .packed, dayCount: 1))
        #expect(relaxed.days[0].dwellMinutes > packed.days[0].dwellMinutes)
    }

    // MARK: clock

    @Test func theFirstStopStartsWhenTheDayOpens() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1,
                        dayStartMinutes: 600, dayEndMinutes: 1_140))
        #expect(trip.days[0].stops[0].arrivalMinutes == 600)
    }

    @Test func arrivalsAreMonotonicWithinADay() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1))
        let arrivals = trip.days[0].stops.map(\.arrivalMinutes)
        #expect(arrivals == arrivals.sorted())
    }

    @Test func onlyTheFirstStopOfADayHasNoInboundLeg() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1))
        let stops = trip.days[0].stops
        #expect(stops[0].legTravelSeconds == nil)
        #expect(stops.dropFirst().allSatisfy { $0.legTravelSeconds != nil })
    }

    // MARK: lunch and fixed blocks

    @Test func lunchIsAddedByDefault() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1))
        #expect(trip.days[0].blocks.contains { $0.spec.kind == .meal })
    }

    @Test func lunchCanBeTurnedOff() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1, includeLunch: false))
        #expect(!trip.days[0].blocks.contains { $0.spec.kind == .meal })
    }

    @Test func aDeclaredArrivalBlockIsPlacedOnItsDay() {
        let arrival = FixedBlockSpec(kind: .arrival, title: "Train from Naples",
                                     startMinutes: 840, durationMinutes: 45)
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1,
                        fixedBlocks: [0: [arrival]]))
        #expect(trip.days[0].blocks.contains { $0.spec.kind == .arrival })
    }

    /// A declared block eats into the day's capacity. Without reserving it, the
    /// planner packs the same seven stops it would fit on a free day and then
    /// overruns once the block is laid onto the clock.
    @Test func aDeclaredBlockIsReservedWhenFillingTheDay() {
        let curatorVisit = FixedBlockSpec(kind: .custom, title: "Afternoon with a curator",
                                          startMinutes: 660, durationMinutes: 180)
        let freeDay = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1))
        let bookedDay = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 1,
                        fixedBlocks: [0: [curatorVisit]]))

        #expect(freeDay.days[0].stops.count == 7)
        #expect(bookedDay.days[0].stops.count == 6)
        #expect(bookedDay.unplacedSiteIds.count == 1)
    }

    // MARK: multi-city splitting

    @Test func citiesAreSpreadAcrossDays() {
        let sites = [
            site("r1", 41.89, 12.49, city: "rome"),
            site("r2", 41.90, 12.45, city: "rome"),
            site("v1", 44.42, 12.20, city: "ravenna"),
            site("v2", 44.41, 12.19, city: "ravenna"),
        ]
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: sites, mode: .driving, dayCount: 2))
        #expect(trip.days.count == 2)
        for day in trip.days {
            #expect(Set(day.stops.compactMap(\.site.cityId)).count == 1)
        }
    }

    /// "Three days in Rome" — one city, more sites than a single day holds.
    /// This is the app's most common trip and must not collapse into one
    /// overstuffed day.
    @Test func aBigCityIsSplitAcrossTheAvailableDays() {
        let many = (0..<30).map {
            site("m\($0)", 41.88 + Double($0 % 6) * 0.003,
                 12.47 + Double($0 / 6) * 0.003, city: "rome", .church, .major)
        }
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: many, mode: .walking, dayCount: 3))
        #expect(trip.days.count == 3)
        #expect(trip.days.allSatisfy { !$0.stops.isEmpty })
        // Thirty major churches cannot fit in three days; the rest are reported.
        #expect(!trip.unplacedSiteIds.isEmpty)
        let placed = trip.days.flatMap { $0.stops.map(\.site.id) }
        #expect(Set(placed).isDisjoint(with: Set(trip.unplacedSiteIds)))
        #expect(placed.count + trip.unplacedSiteIds.count == 30)
    }

    /// `dayCount` is a maximum, not a quota — the planner never pads out empty
    /// days just because the user allowed for more.
    @Test func dayCountIsAMaximumNotAQuota() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 5))
        #expect(trip.days.count == 1)
        #expect(trip.unplacedSiteIds.isEmpty)
    }

    @Test func sitesThatDoNotFitAreReportedRatherThanDropped() {
        // Three distant cities, one day: two cities cannot be placed.
        let sites = [
            site("a", 41.89, 12.49, city: "rome"),
            site("b", 44.42, 12.20, city: "ravenna"),
            site("c", 41.00, 28.98, city: "istanbul"),
        ]
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: sites, mode: .driving, dayCount: 1))
        #expect(trip.days.count == 1)
        #expect(trip.unplacedSiteIds.count == 2)
        let placed = trip.days.flatMap { $0.stops.map(\.site.id) }
        #expect(Set(placed).union(trip.unplacedSiteIds) == ["a", "b", "c"])
    }

    // MARK: diagnostics

    @Test func tooManyCitiesForTheDaysIsDiagnosed() {
        let sites = [
            site("a", 41.89, 12.49, city: "rome"),
            site("b", 44.42, 12.20, city: "ravenna"),
            site("c", 41.00, 28.98, city: "istanbul"),
        ]
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: sites, mode: .driving, dayCount: 1))
        #expect(trip.diagnostics.contains(
            .tooManyPlacesForDays(placeCount: 3, dayCount: 1)))
    }

    /// Four sites under three cityIds, 285 m apart — one town, one day. The
    /// day-count diagnostic must count day-sized clusters, not cityIds, or the
    /// plan tells the user to extend a trip that already fits with hours spare.
    @Test func oneTownWithSeveralCityIdsDoesNotAskForMoreDays() {
        let sites = [
            site("upper",  36.6885, 23.0545, city: "monemvasia-upper-town"),
            site("church", 36.6870, 23.0530, city: "monemvasia"),
            site("kastro", 36.6878, 23.0538, city: "monemvasia-upper-and-lower-town"),
            site("museum", 36.6872, 23.0532, city: "monemvasia", .museum, .minor),
        ]
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: sites, mode: .walking, dayCount: 1))

        #expect(trip.days.count == 1)
        #expect(trip.days[0].stops.count == 4)
        #expect(trip.unplacedSiteIds.isEmpty)
        #expect(!trip.diagnostics.contains { if case .tooManyPlacesForDays = $0 { true } else { false } })
    }

    @Test func aRoomyDayIsDiagnosedAsHavingSlack() {
        let sites = [site("a", 41.89, 12.49, city: "rome")]
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: sites, mode: .walking, dayCount: 1))
        #expect(trip.diagnostics.contains { if case .largeSlack = $0 { true } else { false } })
    }

    /// Thirty major churches over three days cannot all fit. The sites that get
    /// dropped must be announced, not just listed in `unplacedSiteIds`.
    @Test func droppedSitesGetADiagnostic() {
        let many = (0..<30).map {
            site("m\($0)", 41.88 + Double($0 % 6) * 0.003,
                 12.47 + Double($0 / 6) * 0.003, city: "rome", .church, .major)
        }
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: many, mode: .walking, dayCount: 3))
        #expect(!trip.unplacedSiteIds.isEmpty)
        #expect(trip.diagnostics.contains(.sitesDidNotFit(siteIds: trip.unplacedSiteIds)))
    }

    // MARK: degenerate inputs

    @Test func noSitesProducesNoDaysAndNoCrash() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: [], mode: .walking, dayCount: 3))
        #expect(trip.days.isEmpty)
        #expect(trip.unplacedSiteIds.isEmpty)
    }

    @Test func zeroDaysProducesNoDaysAndEverythingUnplaced() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: romeDay, mode: .walking, dayCount: 0))
        #expect(trip.days.isEmpty)
        #expect(Set(trip.unplacedSiteIds) == Set(romeDay.map(\.id)))
    }

    @Test func oneSiteIsAValidTrip() {
        let trip = ItineraryPlanner.plan(
            TripRequest(sites: [site("solo", 41.0, 28.9, city: "istanbul")],
                        mode: .walking, dayCount: 1))
        #expect(trip.days.count == 1)
        #expect(trip.days[0].stops.count == 1)
        #expect(trip.days[0].travelMinutes == 0)
    }

    @Test func planningIsDeterministic() {
        let request = TripRequest(sites: romeDay, mode: .walking, dayCount: 2)
        let a = ItineraryPlanner.plan(request)
        let b = ItineraryPlanner.plan(request)
        #expect(a == b)
    }
}

/// M7a's central constraint: the domain layer must stay free of platform
/// frameworks so it can be reasoned about and tested without a simulator.
/// If this fails, something imported a framework into `Core/Planner/Domain/`.
struct PlannerDomainPurityTests {
    private static let forbidden = ["SwiftUI", "UIKit", "MapKit", "SwiftData", "Combine"]

    @Test func domainSourcesImportOnlyFoundation() throws {
        let root = URL(fileURLWithPath: #filePath)      // .../ByzantineTrailTests/ItineraryPlannerTests.swift
            .deletingLastPathComponent()                 // .../ByzantineTrailTests
            .deletingLastPathComponent()                 // repo root
            .appendingPathComponent("ByzantineTrail/Core/Planner/Domain")

        let files = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        #expect(!files.isEmpty, "found no domain sources at \(root.path)")

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for framework in Self.forbidden {
                #expect(!text.contains("import \(framework)"),
                        "\(file.lastPathComponent) imports \(framework)")
            }
        }
    }
}
