import SwiftUI
import RTPCore
import RTPProviders

/// One button shown in `MapPlaceDetailCard`'s action row. The card itself
/// carries no phase logic — the active phase (`TripWorkspaceModel`) decides
/// which actions make sense (e.g. "Add as POI…" in Phase 2, "Use as
/// Tonight's Overnight" in Phase 3) and supplies them here, each receiving
/// the best-available resolved `PlaceDetails` when tapped.
public struct MapPlaceAction: Identifiable {
    public let id = UUID()
    public var title: String
    public var systemImage: String?
    public var isEnabled: Bool
    public var handler: (PlaceDetails) -> Void

    public init(title: String, systemImage: String? = nil, isEnabled: Bool = true, handler: @escaping (PlaceDetails) -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.handler = handler
    }
}

/// The overlay card shown bottom-left on the map for a picked place — a
/// resolved map click or a search/lodging result pin. Since SwiftUI's
/// `mapFeatureSelectionAccessory` (Apple's automatic info callout) is
/// unavailable on macOS entirely, this is a custom replacement
/// (docs/CONCEPT.md §1.5 "Phase 2 — Points of interest", §2.9 risks).
struct MapPlaceDetailCard: View {
    let selection: MapPlaceSelection
    @Bindable var model: MapPlaceDetailModel
    let actions: [MapPlaceAction]
    let footnote: String?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if model.isLoading {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading details\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let details = model.details {
                detailRows(details)
            }
            Divider()
            HStack {
                ForEach(actions) { action in
                    Button(action.title) {
                        action.handler(model.resolvedDetails(for: selection))
                    }
                    .disabled(!action.isEnabled)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 8, y: 2)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.details?.title.isEmpty == false ? model.details!.title : selection.fallbackTitle)
                    .font(.headline)
                if let category = model.details?.category {
                    Text(category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private func detailRows(_ details: PlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let address = details.address {
                Label(address, systemImage: "mappin.and.ellipse")
            }
            if let phoneNumber = details.phoneNumber {
                Label(phoneNumber, systemImage: "phone")
            }
            if let url = details.url {
                Link(destination: url) {
                    Label(url.host ?? url.absoluteString, systemImage: "link")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
}
