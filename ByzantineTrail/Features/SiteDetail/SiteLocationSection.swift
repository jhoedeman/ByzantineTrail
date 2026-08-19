import SwiftUI
import MapKit

struct SiteLocationSection: View {
    let site: Site
    let theme: Theme
    @Environment(\.openURL) private var openURL

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: site.coordinate.lat, longitude: site.coordinate.lon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)

            if let address = site.address, !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }

            Text(String(format: "%.4f, %.4f", site.coordinate.lat, site.coordinate.lon))
                .font(.caption)
                .foregroundStyle(theme.textDisabled)

            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))) {
                Marker(site.name, coordinate: coordinate)
                    .tint(theme.tierMajor)
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(false)

            Button {
                // Open the site as a pin at its coordinates — no directions.
                // A reference/catalog app shouldn't route from the user's
                // location; they can start directions themselves in Maps.
                SiteDetailFormatter
                    .mapItem(latitude: site.coordinate.lat, longitude: site.coordinate.lon, name: site.name)
                    .openInMaps()
            } label: {
                Label("Open in Maps", systemImage: "map.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentPrimary)

            // Secondary alternative. The universal https link opens the Google
            // Maps app when installed and the Google Maps website otherwise,
            // so it needs no URL scheme or LSApplicationQueriesSchemes entry.
            Button {
                openURL(SiteDetailFormatter.googleMapsURL(
                    latitude: site.coordinate.lat, longitude: site.coordinate.lon))
            } label: {
                Label("Open in Google Maps", systemImage: "globe")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(theme.accentPrimary)
        }
    }
}
