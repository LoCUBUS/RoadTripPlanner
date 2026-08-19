import SwiftUI
import MapKit
import RTPCore
import RTPProviders

/// The shared, reusable map surface used by phases 1–3: renders anchor/POI
/// annotations and route polylines, supports searching for a place, and
/// dropping a pin with a long press — all funnelled through simple callbacks
/// so each phase's editor decides what "adding a point" means
/// (docs/CONCEPT.md §1.3 P3, §2.8).
///
/// Note: tapping Apple Maps' own built-in POI icons (`Map(selection:)` with
/// `MapFeature`) is intentionally not used here — `MapFeature` does not
/// conform to `Hashable`/`Equatable` on macOS in this SDK, so it cannot be
/// used in a target shared between iOS and macOS. Search + long-press cover
/// "select any point interactively" on both platforms.
public struct MapCanvasView: View {
    public var annotations: [MapCanvasAnnotation]
    public var routePolylines: [[Coordinate]]
    public var searchRegion: MapRegion
    public var onSelectAnnotation: (MapCanvasAnnotation) -> Void
    public var onSelectSearchResult: (PlaceResult) -> Void
    public var onLongPress: (Coordinate) -> Void

    @State private var searchViewModel: MapSearchViewModel
    @State private var searchText: String = ""
    @State private var cameraPosition: MapCameraPosition

    public init(
        annotations: [MapCanvasAnnotation],
        routePolylines: [[Coordinate]] = [],
        searchRegion: MapRegion,
        provider: any MapProvider,
        onSelectAnnotation: @escaping (MapCanvasAnnotation) -> Void = { _ in },
        onSelectSearchResult: @escaping (PlaceResult) -> Void = { _ in },
        onLongPress: @escaping (Coordinate) -> Void = { _ in }
    ) {
        self.annotations = annotations
        self.routePolylines = routePolylines
        self.searchRegion = searchRegion
        self.onSelectAnnotation = onSelectAnnotation
        self.onSelectSearchResult = onSelectSearchResult
        self.onLongPress = onLongPress
        _searchViewModel = State(initialValue: MapSearchViewModel(provider: provider))
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(
                center: searchRegion.center.clLocationCoordinate2D,
                span: MKCoordinateSpan(latitudeDelta: searchRegion.latitudeDelta, longitudeDelta: searchRegion.longitudeDelta)
            )
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            mapReader
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search for a place", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, newValue in
                        searchViewModel.updateQuery(newValue, region: searchRegion)
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchViewModel.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(8)

            if searchViewModel.isSearching {
                ProgressView()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else if let errorMessage = searchViewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else if !searchViewModel.results.isEmpty {
                List(searchViewModel.results) { result in
                    Button {
                        onSelectSearchResult(result)
                        searchText = ""
                        searchViewModel.clear()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(result.title)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(maxHeight: 220)
            }
        }
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
