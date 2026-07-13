import Foundation
import MapKit

enum SiteDetailFormatter {
    /// Apple Maps universal link for a coordinate + name.
    static func mapsURL(latitude: Double, longitude: Double, name: String) -> URL {
        var comps = URLComponents(string: "https://maps.apple.com/")!
        comps.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: name),
        ]
        return comps.url!
    }

    /// MKMapItem for "Open in Maps" / directions.
    static func mapItem(latitude: Double, longitude: Double, name: String) -> MKMapItem {
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        item.name = name
        return item
    }

    /// Share message: "Name — summary" (or just the name when no summary).
    static func shareMessage(name: String, summary: String?) -> String {
        if let summary, !summary.isEmpty { return "\(name) — \(summary)" }
        return name
    }

    /// Split Markdown into paragraphs on blank lines and parse each; nil/blank → [].
    static func descriptionParagraphs(_ markdown: String?) -> [AttributedString] {
        guard let markdown,
              !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return markdown
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { try? AttributedString(markdown: $0) }
    }
}
