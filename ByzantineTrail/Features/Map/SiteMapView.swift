import SwiftUI
import MapKit

/// SwiftUI-facing MKMapView. All UIKit lives here (Global Constraint: UIKit
/// stays in Features/Map/). Native clustering via `clusteringIdentifier`.
struct SiteMapView: UIViewRepresentable {
    let annotations: [SiteAnnotation]
    let theme: Theme
    /// Parent bumps this to request a camera re-fit (e.g. filter changed).
    let fitToken: Int
    let onSelectSite: (Site) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelectSite: onSelectSite) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = false
        map.register(SiteMarkerView.self,
                     forAnnotationViewWithReuseIdentifier: SiteMarkerView.reuseID)
        map.register(SiteClusterView.self,
                     forAnnotationViewWithReuseIdentifier: SiteClusterView.reuseID)
        context.coordinator.theme = theme
        map.addAnnotations(annotations)
        // Initial camera fit is deferred to updateUIView: makeUIView runs before
        // SwiftUI lays the map out (frame is .zero here), so regionThatFits cannot
        // aspect-correct the span yet — and burning the fitToken now would suppress
        // the post-layout fit. updateUIView runs after layout with a valid frame.
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.theme = theme
        context.coordinator.onSelectSite = onSelectSite

        // Diff annotations by site id so unchanged pins keep identity.
        let current = map.annotations.compactMap { $0 as? SiteAnnotation }
        let currentIDs = Set(current.map(\.site.id))
        let nextIDs = Set(annotations.map(\.site.id))
        if currentIDs != nextIDs {
            let toRemove = current.filter { !nextIDs.contains($0.site.id) }
            let toAdd = annotations.filter { !currentIDs.contains($0.site.id) }
            map.removeAnnotations(toRemove)
            map.addAnnotations(toAdd)
        }

        // Re-apply the current theme to on-screen pins so a light/dark switch
        // (Profile appearance picker) repaints existing markers, not just newly
        // dequeued ones. Cluster badges are theme-independent by design.
        for annotation in map.annotations {
            if let markerView = map.view(for: annotation) as? SiteMarkerView {
                markerView.apply(theme: theme)
            }
        }

        context.coordinator.fitOnce(map, to: annotations, lastToken: fitToken)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelectSite: (Site) -> Void
        var theme: Theme?
        private var appliedFitToken: Int?

        init(onSelectSite: @escaping (Site) -> Void) {
            self.onSelectSite = onSelectSite
        }

        /// Animate the camera to fit `annotations` once per new `fitToken`.
        func fitOnce(_ map: MKMapView, to annotations: [SiteAnnotation], lastToken: Int) {
            guard appliedFitToken != lastToken else { return }
            let coords = annotations.map(\.coordinate)
            // Only consume the token once we actually have something to fit — an
            // empty first pass (e.g. catalog still loading) must not suppress the
            // fit that should happen when sites arrive on the same token.
            guard let region = MapRegionMath.boundingRegion(for: coords) else { return }
            appliedFitToken = lastToken
            map.setRegion(map.regionThatFits(region), animated: true)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: SiteClusterView.reuseID, for: annotation) as! SiteClusterView
                view.apply(theme: theme)
                return view
            }
            guard annotation is SiteAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: SiteMarkerView.reuseID, for: annotation) as! SiteMarkerView
            view.apply(theme: theme)
            return view
        }

        // Tap on the callout's detail accessory → open detail sheet.
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            if let site = (view.annotation as? SiteAnnotation)?.site {
                onSelectSite(site)
            }
        }
    }
}

/// Tier-colored balloon pin. Native clustering via `clusteringIdentifier`.
final class SiteMarkerView: MKMarkerAnnotationView {
    static let reuseID = "SiteMarker"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "site"
        canShowCallout = true
        rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        glyphImage = UIImage(systemName: "building.columns.fill")
        // .defaultHigh (not .required): .required annotations are always shown and
        // are NOT clustered, which would defeat the clusteringIdentifier above.
        displayPriority = .defaultHigh
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Clear selection visuals before this view is recycled — otherwise a pin
    // dequeued for an unselected annotation could inherit a prior selection's
    // enlarge + glow (e.g. the selected pin gets filtered out and its view is reused).
    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
        layer.shadowRadius = 0
        layer.shadowOpacity = 0
    }

    func apply(theme: Theme?) {
        guard let theme, let site = (annotation as? SiteAnnotation)?.site else { return }
        markerTintColor = UIColor(site.importance.tierColor(theme))
        glyphTintColor = UIColor(Color(hex: Palette.stone950))
    }

    // Enlarge + gold glow on selection (§5.3 "selected pin enlarged w/ Gold-300
    // stroke + shadow"). A layer.border would draw a rectangle around the view's
    // bounds, not the balloon; a shadow follows the balloon's actual shape.
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        let scale: CGFloat = selected ? 1.35 : 1.0
        UIView.animate(withDuration: animated ? 0.15 : 0) {
            self.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        layer.shadowColor = UIColor(Color(hex: Palette.gold300)).cgColor
        layer.shadowRadius = selected ? 6 : 0
        layer.shadowOpacity = selected ? 0.9 : 0
        layer.shadowOffset = .zero
    }
}

/// Circular cluster badge: Stone-950 fill, Gold-400 count text (§5.3).
final class SiteClusterView: MKAnnotationView {
    static let reuseID = "SiteCluster"
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        collisionMode = .circle
        centerOffset = .zero
        layer.cornerRadius = 20
        layer.masksToBounds = true
        label.frame = bounds
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(theme: Theme?) {
        backgroundColor = UIColor(Color(hex: Palette.stone950))
        label.textColor = UIColor(Color(hex: Palette.gold400))
        if let cluster = annotation as? MKClusterAnnotation {
            label.text = "\(cluster.memberAnnotations.count)"
        }
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        apply(theme: nil) // colors are theme-independent per §5.3
    }
}
