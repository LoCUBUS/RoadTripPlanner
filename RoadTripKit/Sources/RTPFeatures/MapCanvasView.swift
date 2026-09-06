import SwiftUI
import MapKit
import RTPCore
import RTPProviders

/// The shared, reusable map surface used by phases 1–5: renders anchor/POI
/// annotations and route polylines, and supports both a long press (drops a
/// plain pin — used by Phase 3's manual lodging pin and Phase 5's photo
/// pinning) and a single click (resolves the nearest real place and shows a
/// detail card) — all funnelled through simple callbacks so each phase's
/// workspace decides what "adding a point" means (docs/CONCEPT.md §1.3 P3,
/// §2.8). Text search now lives in each phase's own inspector field
/// (Corridor, POI) instead of here, since a single shared map search
/// couldn't apply per-phase rules (e.g. the 10 km absorption rule) before a
/// point was picked; search/lodging results are instead rendered here as
/// `.searchResult` pins, clickable like any other.
///
/// SwiftUI's `MapFeature` selection (Apple's own "tap a built-in POI icon"
/// API) is unavailable on macOS entirely — `mapFeatureSelectionAccessory`,
/// `mapFeatureSelectionContent`, and the `Map(selection: Binding<MapFeature?>)`
/// initializer are all `@available(macOS, unavailable)`, and MapKit itself
/// has no `MKMapFeatureAnnotation` on macOS (docs/CONCEPT.md §2.9 risks).
/// So a plain click is resolved with a best-effort heuristic instead:
/// `MapPlaceDetailModel` searches for the nearest real place within a
/// zoom-scaled radius of the click, falling back to a reverse geocode.
public struct MapCanvasView: View {
    public var annotations: [MapCanvasAnnotation]
    public var routePolylines: [[Coordinate]]
    public var searchRegion: MapRegion
    public var mapProvider: any MapProvider
    public var placeSelectionEnabled: Bool
    public var onSelectAnnotation: (MapCanvasAnnotation) -> Void
    public var onLongPress: (Coordinate) -> Void
    public var placeActions: () -> [MapPlaceAction]
    public var placeFootnote: () -> String?

    @State private var cameraPosition: MapCameraPosition
    @State private var activeSelection: MapPlaceSelection?
    @State private var detailModel: MapPlaceDetailModel
    @State private var currentSpanLatitudeDelta: Double

    public init(
        annotations: [MapCanvasAnnotation],
        routePolylines: [[Coordinate]] = [],
        searchRegion: MapRegion,
        mapProvider: any MapProvider,
        placeSelectionEnabled: Bool = false,
        onSelectAnnotation: @escaping (MapCanvasAnnotation) -> Void = { _ in },
        onLongPress: @escaping (Coordinate) -> Void = { _ in },
        placeActions: @escaping () -> [MapPlaceAction] = { [] },
        placeFootnote: @escaping () -> String? = { nil }
    ) {
        self.annotations = annotations
        self.routePolylines = routePolylines
        self.searchRegion = searchRegion
        self.mapProvider = mapProvider
        self.placeSelectionEnabled = placeSelectionEnabled
        self.onSelectAnnotation = onSelectAnnotation
        self.onLongPress = onLongPress
        self.placeActions = placeActions
        self.placeFootnote = placeFootnote
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(
                center: searchRegion.center.clLocationCoordinate2D,
                span: MKCoordinateSpan(latitudeDelta: searchRegion.latitudeDelta, longitudeDelta: searchRegion.longitudeDelta)
            )
        ))
        _detailModel = State(initialValue: MapPlaceDetailModel(mapProvider: mapProvider))
        _currentSpanLatitudeDelta = State(initialValue: searchRegion.latitudeDelta)
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
                            handleAnnotationTap(annotation)
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
            .gesture(clickGesture(proxy: proxy))
            .onMapCameraChange(frequency: .onEnd) { context in
                currentSpanLatitudeDelta = context.region.span.latitudeDelta
            }
            .onChange(of: searchResultCoordinates) { _, newValue in
                fitCamera(to: newValue)
            }
            .overlay(alignment: .bottomLeading) {
                if let selection = activeSelection {
                    MapPlaceDetailCard(
                        selection: selection,
                        model: detailModel,
                        actions: wrappedActions(),
                        footnote: placeFootnote(),
                        onClose: { closePlaceDetail() }
                    )
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: activeSelection)
        }
    }

    private func handleAnnotationTap(_ annotation: MapCanvasAnnotation) {
        onSelectAnnotation(annotation)
        guard placeSelectionEnabled, annotation.style == .searchResult, let placeDetails = annotation.placeDetails else { return }
        let selection = MapPlaceSelection(coordinate: annotation.coordinate, fallbackTitle: annotation.title)
        activeSelection = selection
        detailModel.present(placeDetails)
    }

    /// Wraps each externally-supplied action so picking any of them also
    /// dismisses the card — every action either completes the interaction
    /// (adds a POI/overnight) or opens a follow-up sheet, so there is never
    /// a reason to keep the card open afterwards.
    private func wrappedActions() -> [MapPlaceAction] {
        placeActions().map { action in
            MapPlaceAction(title: action.title, systemImage: action.systemImage, isEnabled: action.isEnabled) { details in
                action.handler(details)
                closePlaceDetail()
            }
        }
    }

    private func closePlaceDetail() {
        detailModel.dismiss()
        activeSelection = nil
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

    /// A quick click resolves the nearest real place at the clicked
    /// coordinate (docs/CONCEPT.md §2.5 "Selecting a map place"). Uses a
    /// plain (non-simultaneous) `DragGesture(minimumDistance: 0)` rather
    /// than `TapGesture`, since `MapReader`'s `proxy.convert` needs a
    /// concrete location; attaching it as a regular (not simultaneous)
    /// gesture lets SwiftUI's normal precedence give annotation `Button`s
    /// first claim on their own taps, so clicking a pin never also opens
    /// the resolved-place card underneath it.
    private func clickGesture(proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                guard placeSelectionEnabled else { return }
                let translation = value.translation
                guard abs(translation.width) < 4, abs(translation.height) < 4 else { return }
                guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                let selection = MapPlaceSelection(coordinate: Coordinate(coordinate))
                activeSelection = selection
                detailModel.load(selection, radiusMeters: lookupRadiusMeters)
            }
    }

    /// Scales the nearest-place search radius with the current zoom level —
    /// a click at street-level zoom should only match something within a
    /// few dozen meters, while a click zoomed out to a whole region should
    /// tolerate a few kilometers. 1° latitude ≈ 111 km.
    private var lookupRadiusMeters: Double {
        let approxMeters = currentSpanLatitudeDelta * 111_000 * 0.06
        return min(5_000, max(150, approxMeters))
    }

    /// The coordinates of every `.searchResult` pin currently shown —
    /// tracked separately so newly-arrived search/lodging results can pan
    /// the camera to include them without reacting to every other
    /// annotation change (e.g. reordering POIs).
    private var searchResultCoordinates: [Coordinate] {
        annotations.filter { $0.style == .searchResult }.map(\.coordinate)
    }

    /// Pans/zooms the camera to fit newly-arrived search results — a text
    /// search often returns matches outside the currently visible area, and
    /// without this the new pins would be invisible until the user
    /// manually pans to find them.
    private func fitCamera(to coordinates: [Coordinate]) {
        guard !coordinates.isEmpty else { return }
        let clCoordinates = coordinates.map(\.clLocationCoordinate2D)
        let minLatitude = clCoordinates.map(\.latitude).min()!
        let maxLatitude = clCoordinates.map(\.latitude).max()!
        let minLongitude = clCoordinates.map(\.longitude).min()!
        let maxLongitude = clCoordinates.map(\.longitude).max()!
        let center = CLLocationCoordinate2D(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLatitude - minLatitude) * 1.6),
            longitudeDelta: max(0.02, (maxLongitude - minLongitude) * 1.6)
        )
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}
