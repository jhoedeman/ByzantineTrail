import Foundation

enum SortField: String, CaseIterable, Identifiable {
    case name, importance, country, city
    var id: String { rawValue }
    var displayLabel: String {
        switch self {
        case .name: "Name"
        case .importance: "Importance"
        case .country: "Country"
        case .city: "City"
        }
    }
}

/// Pure transform: search → filter → sort. Views hold one of these in @State
/// and bind the UI to its fields. M4/M5 add rating/state sort fields and
/// filter flags without changing this pipeline's shape.
struct SiteQuery {
    var searchText: String = ""
    var filter: SiteFilter = SiteFilter()
    var sortField: SortField = .name
    var ascending: Bool = true

    func apply(to sites: [Site], cityNames: [String: String],
               userState: UserStateSnapshot = .empty) -> [Site] {
        let searched = sites.filter { matchesSearch($0, cityNames: cityNames) }
        let filtered = searched.filter { filter.matches($0, flags: userState.flags(for: $0.id)) }
        return sorted(filtered, cityNames: cityNames)
    }

    private func matchesSearch(_ site: Site, cityNames: [String: String]) -> Bool {
        let q = Self.fold(searchText)
        guard !q.isEmpty else { return true }
        var fields = [site.name, site.country, CountryName.localized(site.country)]
        fields.append(contentsOf: site.alternateNames)
        fields.append(contentsOf: site.tags)
        if let cid = site.cityId, let name = cityNames[cid] { fields.append(name) }
        return fields.contains { Self.fold($0).contains(q) }
    }

    private func sorted(_ sites: [Site], cityNames: [String: String]) -> [Site] {
        let asc = sites.sorted { a, b in
            switch sortField {
            case .name:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .importance:
                return a.importance.rank != b.importance.rank
                    ? a.importance.rank < b.importance.rank
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .country:
                let ca = CountryName.localized(a.country), cb = CountryName.localized(b.country)
                return ca != cb
                    ? ca.localizedCaseInsensitiveCompare(cb) == .orderedAscending
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .city:
                let ca = a.cityId.flatMap { cityNames[$0] } ?? ""
                let cb = b.cityId.flatMap { cityNames[$0] } ?? ""
                return ca != cb
                    ? ca.localizedCaseInsensitiveCompare(cb) == .orderedAscending
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
        return ascending ? asc : asc.reversed()
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
