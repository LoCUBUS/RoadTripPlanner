import SwiftUI
import MapKit
import RTPCore
import RTPProviders

/// The shared, reusable map surface used by phases 1–3: renders anchor/POI
/// annotations and route polylines, and supports dropping a pin with a long
/// press — all funnelled through simple callbacks so each phase's editor
/// decides what "adding a point" means (docs/CONCEPT.md §1.3 P3, §2.8).
/// Text search now lives in each phase's own inspector field (Corridor,
/// POI) instead of here, since a single shared map search couldn't apply
/// per-phase rules (e.g. the 10 km absorption rule) before a point was
/// picked.
///
/// Note: tapping Apple Maps' own built-in POI icons (`Map(selection:)` with
/// `MapFeature`) is intentionally not used here — `MapFeature` does not
/// conform to `Hashable`/`Equatable` on macOS in this SDK, so it cannot be
/// used in a target shared between iOS and macOS. Long-press covers
/// "select any point interactively" on both platforms; search is offered
/// per-phase instead.
public struct MapCanvasView: View {
    public var annotations: [MapCanvasAnnotation]
    public var routePolylines: [[Coordinate]]
    public var searchRegion: MapRegion
    public var onSelectAnnotation: (MapCanvasAnnotation) -> Void
    public var onLongPress: (Coordinate) -> Void

    @State private var cameraPosition: MapCameraPosition

    public init(
        annotations: [MapCanvasAnnotation],
        routePolylines: [[Coordinate]] = [],
        searchRegion: MapRegion,
        onSelectAnnotation: @escaping (MapCanvasAnnotation) -> Void = { _ in },
        onLongPress: @escaping (Coordinate) -> Void = { _ in }
    ) {
        self.annotations = annotations
        self.routePolylines = routePolylines
        self.searchRegion = searchRegion
        self.onSelectAnnotation = onSelectAnnotation
        self.onLongPress = onLongPress
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(
                center: searchRegion.center.clLocationCoordinate2D,
                span: MKCoordinateSpan(latitudeDelta: searchRegion.latitudeDelta, longitudeDelta: searchRegion.longitudeDelta)
            )
        ))
    }

    public var body: some View {
        mapReader
    }

    private var mapReader: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                ForEach(annotations) { annotation in
                    Annotation(annotation.title, coordinate: annotation.coordinate.clLocationCoordinate2D) {
                        Button {
                            onSelectAnnotation(annotation)
                        } label: {
                            Image(systemName: annotation.style.systemImage)
                                .symbolRenderingMode(.multicolor)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(annotation.style.accessibilityDescription): \(annotation.title)")
                    }
                }

                ForEach(Array(routePolylines.enumerated()), id: \.offset) { _, polyline in
                    MapPolyline(coordinates: polyline.map(\.clLocationCoordinate2D))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(pointsOfInterest: .all))
            .simultaneousGesture(longPressGesture(proxy: proxy))
        }
    }

    private func longPressGesture(proxy: MapProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onEnded { value in
                guard case .second(true, let drag) = value, let location = drag?.location else { return }
                guard let coordinate = proxy.convert(location, from: .local) else { return }
                onLongPress(Coordinate(coordinate))
            }
    }
}
