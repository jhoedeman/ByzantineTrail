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
        let url = resolver?.fullURL(for: photo)
        return ZStack(alignment: .bottomLeading) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                default:
                    ZStack { theme.bgCardAlt; ProgressView() }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { if let url { zoom = ZoomItem(url: url) } }

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
