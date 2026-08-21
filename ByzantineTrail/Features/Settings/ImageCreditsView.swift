import SwiftUI

/// Lists third-party / licensed photographs with their attribution and a link to
/// the governing license. Owner photos ("Photo: John Hoedeman") are not listed;
/// only photos carrying a `licenseURL` appear here. A standing note documents the
/// resizing / metadata-stripping applied to all images (an "indicate changes"
/// requirement of the CC licenses, satisfied globally rather than per photo).
struct ImageCreditsView: View {
    @Environment(CatalogStore.self) private var catalogStore

    private struct Credit: Identifiable {
        let id: String          // photo id (unique across the catalog)
        let credit: String
        let licenseURL: URL?
    }

    private struct SiteGroup: Identifiable {
        let id: String          // site id
        let name: String
        let credits: [Credit]
    }

    private var groups: [SiteGroup] {
        catalogStore.sites.compactMap { site in
            let credits: [Credit] = site.photos.compactMap { photo in
                guard let license = photo.licenseURL, !license.isEmpty else { return nil }
                return Credit(id: photo.id,
                              credit: photo.credit ?? "",
                              licenseURL: URL(string: license))
            }
            guard !credits.isEmpty else { return nil }
            return SiteGroup(id: site.id, name: site.name, credits: credits)
        }
    }

    var body: some View {
        List {
            Section {
                Text("Photographs credited below are used under the license shown. All images in the app may have been resized and had location and camera metadata removed from their originals.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if groups.isEmpty {
                Section {
                    Text("No third-party images are currently used.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groups) { group in
                    Section(group.name) {
                        ForEach(group.credits) { credit in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(credit.credit)
                                if let url = credit.licenseURL {
                                    Link("View license", destination: url)
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Image Credits")
    }
}
