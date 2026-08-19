import SwiftUI

struct PhotoCarousel: View {
    let site: Site
    let resolver: PhotoResolver?
    let theme: Theme

    private struct ZoomItem: Identifiable { let id = UUID(); let url: URL }
    @State private var zoom: ZoomItem?

    private let height: CGFloat = 260

    var body: some View {
        content
            .fullScreenCover(item: $zoom) { item in
                ZoomableImageView(url: item.url) { zoom = nil }
            }
    }

    @ViewBuilder
    private var content: some View {
        if site.photos.isEmpty || resolver == nil {
            placeholder
        } else {
            TabView {
                ForEach(site.photos) { photo in
                    page(photo)
                }
            }
            .tabViewStyle(.page)
            .frame(height: height)
        }
    }

    private var placeholder: some View {
        ZStack {
            theme.bgCardAlt
            Image(systemName: site.type.iconName)
                .font(.system(size: 56))
                .foregroundStyle(theme.accentPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func page(_ photo: Photo) -> some View {
        // Banner uses the thumbnail: it's bundled (offline first-run) and 500px
        // is ample for a 260pt banner. Full-res streams from photoBaseURL only
        // when tapped (ZoomableImageView), so the carousel never blocks on the
        // network to show a picture.
        let bannerURL = resolver?.thumbURL(for: photo)
        let fullURL = resolver?.fullURL(for: photo)
        return ZStack(alignment: .bottomLeading) {
            AsyncImage(url: bannerURL) { phase in
                switch phase {
                case .success(let image):
                    // Fit (letterbox) so portrait photos show whole rather than
                    // being center-cropped to a horizontal slice; matting is the
                    // card color. Full detail is available on tap (ZoomableImageView).
                    image.resizable().scaledToFit()
                case .failure:
                    placeholder
                default:
                    ZStack { theme.bgCardAlt; ProgressView() }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(theme.bgCardAlt)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { if let fullURL { zoom = ZoomItem(url: fullURL) } }

            if let caption = photo.caption, !caption.isEmpty {
                captionBar(caption, credit: photo.credit)
            }
        }
    }

    private func captionBar(_ caption: String, credit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(theme.textOnImage)
            if let credit, !credit.isEmpty {
                Text(credit)
                    .font(.caption2)
                    .foregroundStyle(theme.textOnImage.opacity(0.8))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.45))   // fixed dark image scrim (always-dark surface)
    }
}
