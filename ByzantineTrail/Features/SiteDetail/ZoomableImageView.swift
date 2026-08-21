import SwiftUI

struct ZoomableImageView: View {
    let url: URL
    var credit: String? = nil
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView().tint(.white)
            }
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = max(1, lastScale * $0.magnification) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 { offset = .zero; lastOffset = .zero }
                    }
            )
            .gesture(
                DragGesture()
                    .onChanged {
                        offset = CGSize(width: lastOffset.width + $0.translation.width,
                                        height: lastOffset.height + $0.translation.height)
                    }
                    .onEnded { _ in
                        if scale <= 1 { offset = .zero; lastOffset = .zero }
                        else { lastOffset = offset }
                    }
            )

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .padding()
            }
            .accessibilityLabel("Close")
        }
        // Credit stays visible over the full-res image (attribution must show
        // here too). allowsHitTesting(false) keeps pinch/pan working underneath.
        .overlay(alignment: .bottom) {
            if let credit, !credit.isEmpty {
                Text(credit)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.5))
                    .allowsHitTesting(false)
            }
        }
    }
}
