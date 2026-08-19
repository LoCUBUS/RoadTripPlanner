import SwiftUI
import PhotosUI
import RTPCore
import RTPProviders

/// Phase 5 journal: import photos from the Photos library, see them pinned
/// where they were taken, caption them, and manually pin any without
/// location metadata (docs/CONCEPT.md §1.5 "Phase 5 — Journal"). Reachable
/// at any time (P1) — typically used during or after the trip.
public struct PhotoJournalView: View {
    @State private var viewModel: PhotoJournalViewModel
    private let mapProvider: any MapProvider

    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var pendingManualPin: TripPhoto?

    public init(trip: Trip, assetResolver: any PhotoAssetResolver, mapProvider: any MapProvider) {
        _viewModel = State(initialValue: PhotoJournalViewModel(trip: trip, assetResolver: assetResolver))
        self.mapProvider = mapProvider
    }

    public var body: some View {
        VStack(spacing: 0) {
            MapCanvasView(
                annotations: mapAnnotations,
                searchRegion: searchRegion,
                provider: mapProvider,
                onLongPress: { coordinate in
                    guard let photo = pendingManualPin else { return }
                    viewModel.pinPhoto(photo, at: coordinate)
                    pendingManualPin = nil
                }
            )
            .frame(minHeight: 260)

            List {
                Section {
                    PhotosPicker(selection: $pickerSelection, matching: .images) {
                        Label("Import Photos", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: pickerSelection) { _, newValue in
                        let identifiers = newValue.compactMap(\.itemIdentifier)
                        Task {
                            await viewModel.importPhotos(identifiers: identifiers)
                            pickerSelection = []
                        }
                    }

                    if viewModel.isImporting {
                        ProgressView("Importing…")
                    }
                }

                if !viewModel.unpinnedPhotos.isEmpty {
                    Section("Needs a Pin") {
                        ForEach(viewModel.unpinnedPhotos) { photo in
                            PhotoRow(photo: photo, viewModel: viewModel)
                            Button {
                                pendingManualPin = photo
                            } label: {
                                Label(
                                    pendingManualPin?.id == photo.id ? "Long-press the map to place this photo" : "Place on Map",
                                    systemImage: "mappin.and.ellipse"
                                )
                            }
                        }
                    }
                }

                if !viewModel.pinnedPhotos.isEmpty {
                    Section("On the Map") {
                        ForEach(viewModel.pinnedPhotos) { photo in
                            PhotoRow(photo: photo, viewModel: viewModel)
                        }
                        .onDelete { offsets in
                            let photos = viewModel.pinnedPhotos
                            for index in offsets {
                                viewModel.removePhoto(photos[index])
                            }
                        }
                    }
                }

                if viewModel.photos.isEmpty {
                    Section {
                        Text("Import photos from your library to build the journal.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Journal")
    }

    private var mapAnnotations: [MapCanvasAnnotation] {
        viewModel.trip.orderedAnchors.map(MapCanvasAnnotation.init(anchor:)) +
            viewModel.pinnedPhotos.compactMap { photo in
                guard let coordinate = photo.coordinate else { return nil }
                return MapCanvasAnnotation(id: photo.id, coordinate: coordinate, title: photo.caption.isEmpty ? "Photo" : photo.caption, style: .photo)
            }
    }

    private var searchRegion: MapRegion {
        if let first = viewModel.trip.orderedAnchors.first {
            return MapRegion(center: first.coordinate, latitudeDelta: 5, longitudeDelta: 5)
        }
        return MapRegion(center: Coordinate(latitude: 48.1351, longitude: 11.5820), latitudeDelta: 10, longitudeDelta: 10)
    }
}

/// One photo row: capture date and an editable caption.
private struct PhotoRow: View {
    let photo: TripPhoto
    let viewModel: PhotoJournalViewModel

    @State private var caption: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(photo.captureDate, style: .date)
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Caption", text: $caption, axis: .vertical)
                .onAppear { caption = photo.caption }
                .onChange(of: caption) { _, newValue in
                    viewModel.setCaption(newValue, for: photo)
                }
        }
    }
}
