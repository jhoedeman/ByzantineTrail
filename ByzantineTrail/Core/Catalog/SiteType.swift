enum SiteType: String, Codable, CaseIterable {
    case church, monastery, fortress, palace, cityWalls, cistern, aqueduct
    case mosaicSite, archaeologicalSite, museum, tower, bridge, other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SiteType(rawValue: raw) ?? .other
    }
}

enum Importance: String, Codable, CaseIterable {
    case major, notable, minor

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Importance(rawValue: raw) ?? .minor
    }
}
