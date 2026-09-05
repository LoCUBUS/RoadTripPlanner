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
/// When `featureSelectionEnabled` is true (Phase 2), tapping one of Apple
/// Maps' own built-in POI icons resolves it to a `MapFeatureTap` and shows
/// a detail card overlay (bottom-left, mirroring Apple Maps' own info
/// card, which `mapFeatureSelectionAccessory` — its automatic
/// equivalent — does not offer on macOS). `MapFeature` itself is never
/// exposed outside this view: it isn't `Hashable`/`Equatable` on macOS in
/// this SDK, so `MapSelection<MKMapItem>` is used only internally and
/// reset after each tap.
public struct MapCanvasView: View {
    public var annotations: [MapCanvasAnnotation]
    public var routePolylines: [[Coordinate]]
    public var searchRegion: MapRegion
    public var mapProvider: any MapProvider
    public var featureSelectionEnabled: Bool
    public var onSelectAnnotation: (MapCanvasAnnotation) -> Void
    public var onLongPress: (Coordinate) -> Void
    public var onAddFeatureAsPOI: (PlaceDetails) -> Void
    public var onAddFeatureAsOvernight: (PlaceDetails) -> Void

    @State private var cameraPosition: MapCameraPosition
    @State private var featureSelection: MapSelection<MKMapItem>?
    @State private var activeFeatureTap: MapFeatureTap?
    @State private var detailModel: MapFeatureDetailModel

    public init(
        annotations: [MapCanvasAnnotation],
        routePolylines: [[Coordinate]] = [],
        searchRegion: MapRegion,
        mapProvider: any MapProvider,
        featureSelectionEnabled: Bool = false,
        onSelectAnnotation: @escaping (MapCanvasAnnotation) -> Void = { _ in },
        onLongPress: @escaping (Coordinate) -> Void = { _ in },
        onAddFeatureAsPOI: @escaping (PlaceDetails) -> Void = { _ in },
        onAddFeatureAsOvernight: @escaping (PlaceDetails) -> Void = { _ in }
    ) {
        self.annotations = annotations
        self.routePolylines = routePolylines
        self.searchRegion = searchRegion
        self.mapProvider = mapProvider
        self.featureSelectionEnabled = featureSelectionEnabled
        self.onSelectAnnotation = onSelectAnnotation
        self.onLongPress = onLongPress
        self.onAddFeatureAsPOI = onAddFeatureAsPOI
        self.onAddFeatureAsOvernight = onAddFeatureAsOvernight
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(
                center: searchRegion.center.clLocationCoordinate2D,
                span: MKCoordinateSpan(latitudeDelta: searchRegion.latitudeDelta, longitudeDelta: searchRegion.longitudeDelta)
            )
        ))
        _detailModel = State(initialValue: MapFeatureDetailModel(mapProvider: mapProvider))
    }

    public var body: some View {
        mapReader
    }

    private var mapReader: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, selection: $featureSelection) {
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
            .onChange(of: featureSelection) { _, newValue in
                handleFeatureSelection(newValue)
            }
            .overlay(alignment: .bottomLeading) {
                if featureSelectionEnabled, let tap = activeFeatureTap {
                    MapFeatureDetailCard(
                        tap: tap,
                        model: detailModel,
                        onAddPOI: { details in
                            onAddFeatureAsPOI(details)
                            closeFeatureDetail()
                        },
                        onAddOvernight: { details in
                            onAddFeatureAsOvernight(details)
                            closeFeatureDetail()
                        },
                        onClose: { closeFeatureDetail() }
                    )
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: activeFeatureTap)
        }
    }

    private func handleFeatureSelection(_ selection: MapSelection<MKMapItem>?) {
        // Reset immediately so tapping the same built-in POI icon twice in a
        // row re-triggers this handler instead of being swallowed as a
        // no-op selection change.
        featureSelection = nil
        guard featureSelectionEnabled, let feature = selection?.feature, let title = feature.title else { return }
        let tap = MapFeatureTap(title: title, coordinate: Coordinate(feature.coordinate))
        activeFeatureTap = tap
        detailModel.load(tap)
    }

    private func closeFeatureDetail() {
        detailModel.dismiss()
        activeFeatureTap = nil
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
