import Testing
@testable import ByzantineTrail

struct VisitDurationTests {
    private func m(_ t: SiteType, _ i: Importance, _ p: Pace = .standard) -> Int {
        VisitDuration.minutes(type: t, importance: i, pace: p)
    }

    // MARK: base values

    @Test func plainChurchUsesTheImportanceBase() {
        #expect(m(.church, .major) == 75)
        #expect(m(.church, .notable) == 30)
        #expect(m(.church, .minor) == 15)
    }

    @Test func typesWithNoRuleUseTheBase() {
        #expect(m(.fortress, .notable) == 30)
        #expect(m(.cistern, .minor) == 15)
        #expect(m(.palace, .major) == 75)
        #expect(m(.baptistery, .notable) == 30)
        #expect(m(.other, .minor) == 15)
    }

    // MARK: type rules

    @Test func museumHasAFloorOf45() {
        #expect(m(.museum, .minor) == 45)     // 15 raised to the floor
        #expect(m(.museum, .notable) == 45)   // 30 raised to the floor
        #expect(m(.museum, .major) == 75)     // already above the floor
    }

    @Test func archaeologicalSitesGetHalfAgain() {
        #expect(m(.archaeologicalSite, .minor) == 25)    // 15 * 1.5 = 22.5 -> 25
        #expect(m(.archaeologicalSite, .notable) == 45)  // 30 * 1.5 = 45
    }

    @Test func monasteriesGetAQuarterMore() {
        #expect(m(.monastery, .minor) == 20)     // 15 * 1.25 = 18.75 -> 20
        #expect(m(.monastery, .notable) == 40)   // 30 * 1.25 = 37.5 -> 40
        #expect(m(.monastery, .major) == 95)     // 75 * 1.25 = 93.75 -> 95
    }

    @Test func singleObjectTypesAreCappedAt15() {
        for t: SiteType in [.column, .triumphalArch, .icon, .tower, .mausoleum, .aqueduct] {
            #expect(m(t, .notable) == 15, "\(t) notable should cap to 15")
            #expect(m(t, .minor) == 15, "\(t) minor is already 15")
        }
    }

    @Test func cityWallsAreCappedAt30() {
        #expect(m(.cityWalls, .notable) == 30)
        #expect(m(.cityWalls, .minor) == 15)   // base already below the cap
    }

    // MARK: the major exemption

    /// The Theodosian Land Walls are the catalog's only major cityWalls site.
    /// Without the exemption the cap would budget six kilometres of the most
    /// formidable fortification in the Byzantine world at half an hour.
    @Test func capsDoNotApplyToMajorSites() {
        #expect(m(.cityWalls, .major) == 75)
    }

    // MARK: pace

    @Test func paceMultipliesTheResult() {
        #expect(m(.church, .major, .relaxed) == 100)  // 75 * 1.3 = 97.5 -> 100
        #expect(m(.church, .major, .packed) == 55)    // 75 * 0.75 = 56.25 -> 55
        #expect(m(.church, .notable, .relaxed) == 40) // 30 * 1.3 = 39 -> 40
        #expect(m(.church, .minor, .packed) == 10)    // 15 * 0.75 = 11.25 -> 10
    }

    @Test func paceMultipliersAreTheSpecValues() {
        #expect(Pace.relaxed.multiplier == 1.3)
        #expect(Pace.standard.multiplier == 1.0)
        #expect(Pace.packed.multiplier == 0.75)
    }

    // MARK: invariants

    @Test func everyCombinationRoundsToAMultipleOfFive() {
        for t in SiteType.allCases {
            for i in Importance.allCases {
                for p in Pace.allCases {
                    let v = m(t, i, p)
                    #expect(v % 5 == 0, "\(t)/\(i)/\(p) produced \(v)")
                    #expect(v >= 5, "\(t)/\(i)/\(p) produced \(v)")
                }
            }
        }
    }

    /// Every type/importance combination, including ones the catalog does not
    /// currently contain. The shipped catalog yields the first eight of these;
    /// 115 arises only from a *major archaeological site*, of which there are
    /// none today (all 48 are notable or minor). If a future catalog adds one,
    /// this test documents what it would get.
    @Test func theFullValueSetIsSmallAndRound() {
        var seen = Set<Int>()
        for t in SiteType.allCases {
            for i in Importance.allCases {
                seen.insert(m(t, i))
            }
        }
        #expect(seen == [15, 20, 25, 30, 40, 45, 75, 95, 115])
    }
}
