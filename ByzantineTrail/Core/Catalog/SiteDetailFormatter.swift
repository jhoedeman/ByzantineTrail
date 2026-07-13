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
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        } else {
            item = legacyMapItem(latitude: latitude, longitude: longitude)
        }
        item.name = name
        return item
    }

    /// Quarantines the pre-iOS-26 placemark initializer. Marking the helper
    /// `@available(deprecated:)` suppresses the deprecation warning for the
    /// intentional legacy call while keeping iOS 17 support.
    @available(iOS, introduced: 17.0, deprecated: 26.0)
    private static func legacyMapItem(latitude: Double, longitude: Double) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
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
