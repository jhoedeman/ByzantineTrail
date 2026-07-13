import Foundation

struct Coordinate: Codable, Equatable { let lat, lon: Double }
struct Period: Codable, Equatable { let century: Int?; let era: String? }

struct Photo: Codable, Equatable, Identifiable {
    let id, thumb, full: String
    let caption, credit: String?
}

struct SiteLink: Codable, Equatable { let title, url: String }
struct City: Codable, Identifiable, Equatable { let id, name: String }

struct Site: Codable, Identifiable, Equatable {
    let id, name: String
    let alternateNames: [String]
    let type: SiteType
    let country: String
    let cityId: String?
    let coordinate: Coordinate
    let address: String?
    let importance: Importance
    let addedInVersion: Int?
    let period: Period?
    let summary, description, hours, entryInfo: String?
    let photos: [Photo]
    let semanticTags: [String]
    let tags: [String]
    let links: [SiteLink]

    enum CodingKeys: String, CodingKey {
        case id, name, alternateNames, type, country, cityId, coordinate, address
        case importance, addedInVersion, period, summary, description, hours
        case entryInfo, photos, semanticTags, tags, links
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        alternateNames = try c.decodeIfPresent([String].self, forKey: .alternateNames) ?? []
        type = try c.decode(SiteType.self, forKey: .type)
        country = try c.decode(String.self, forKey: .country)
        cityId = try c.decodeIfPresent(String.self, forKey: .cityId)
        coordinate = try c.decode(Coordinate.self, forKey: .coordinate)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        importance = try c.decode(Importance.self, forKey: .importance)
        addedInVersion = try c.decodeIfPresent(Int.self, forKey: .addedInVersion)
        period = try c.decodeIfPresent(Period.self, forKey: .period)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        hours = try c.decodeIfPresent(String.self, forKey: .hours)
        entryInfo = try c.decodeIfPresent(String.self, forKey: .entryInfo)
        photos = try c.decodeIfPresent([Photo].self, forKey: .photos) ?? []
        semanticTags = try c.decodeIfPresent([String].self, forKey: .semanticTags) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        links = try c.decodeIfPresent([SiteLink].self, forKey: .links) ?? []
    }
}

struct Catalog: Codable {
    let schemaVersion, catalogVersion: Int
    let generatedAt: String?
    let photoBaseURL: String
    let cities: [City]
    let sites: [Site]
}
