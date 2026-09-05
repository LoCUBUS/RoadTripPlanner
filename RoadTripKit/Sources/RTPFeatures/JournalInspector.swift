import SwiftUI
import PhotosUI
import RTPCore
import RTPProviders

/// Phase 5 inspector: import photos from the Photos library, see them
/// pinned where they were taken, caption them, and arm a photo for manual
/// pinning on the map (docs/CONCEPT.md §1.5 "Phase 5 — Journal"). Manual
/// pinning needs to arm/disarm `TripWorkspaceModel.photoAwaitingPin`, which
/// the workspace then places on the next map long-press, so this inspector
/// takes the whole workspace rather than just the journal view model.
/// Reachable at any time (P1) — typically used during or after the trip.
public struct JournalInspector: View {
    var workspace: TripWorkspaceModel

    public init(workspace: TripWorkspaceModel) {
        self.workspace = workspace
    }

    private var viewModel: PhotoJournalViewModel { workspace.journalViewModel }

    @State private var pickerSelection: [PhotosPickerItem] = []

    public var body: some View {
        Group {
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

            if !viewModel.unpinnedPhotos.isEmpty {
                Divider()
                Text("Needs a Pin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.unpinnedPhotos) { photo in
                    PhotoRow(photo: photo, viewModel: viewModel)
                    Button {
                        workspace.photoAwaitingPin = photo
                    } label: {
                        Label(
                            workspace.photoAwaitingPin?.id == photo.id ? "Long-press the map to place this photo" : "Place on Map",
                            systemImage: "mappin.and.ellipse"
                        )
                    }
                }
            }

            if !viewModel.pinnedPhotos.isEmpty {
                Divider()
                Text("On the Map")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.pinnedPhotos) { photo in
                    PhotoRow(photo: photo, viewModel: viewModel)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.removePhoto(photo)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }

            if viewModel.photos.isEmpty {
                Text("Import photos from your library to build the journal.")
                    .foregroundStyle(.secondary)
            }
        }
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
