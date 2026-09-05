import SwiftUI
import RTPCore
import RTPProviders

/// The overlay card shown bottom-left on the map when a built-in Apple Maps
/// point of interest is tapped in Phase 2 — since `mapFeatureSelectionAccessory`
/// (Apple's automatic info callout) is iOS-only, this replaces it on macOS
/// (docs/CONCEPT.md §1.5 "Phase 2 — Points of interest", §2.9 risks).
struct MapFeatureDetailCard: View {
    let tap: MapFeatureTap
    @Bindable var model: MapFeatureDetailModel
    let onAddPOI: (PlaceDetails) -> Void
    let onAddOvernight: (PlaceDetails) -> Void
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
                Button("Add as POI") { onAddPOI(model.resolvedDetails(for: tap)) }
                Button("Add as Overnight") { onAddOvernight(model.resolvedDetails(for: tap)) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
                Text(model.details?.title.isEmpty == false ? model.details!.title : tap.title)
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
