import SwiftUI
import RTPCore
import RTPProviders

/// Phase 4 summary: a day-by-day itinerary with per-stop Apple Maps
/// hand-off, a visited toggle, and a comment/rating field
/// (docs/CONCEPT.md §1.5 "Phase 4 — Summary"). Reachable at any time (P1);
/// purely reads what the earlier phases already planned.
public struct SummaryView: View {
    @State private var viewModel: SummaryViewModel
    @Environment(\.openURL) private var openURL

    public init(trip: Trip, mapProvider: any MapProvider) {
        _viewModel = State(initialValue: SummaryViewModel(trip: trip, mapProvider: mapProvider))
    }

    public var body: some View {
        List {
            if viewModel.days.isEmpty {
                Section {
                    Text("Plan at least one day in \u{201C}Plan Overnights\u{201D} to see a summary here.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(viewModel.days) { day in
                Section {
                    dayHeader(day)
                    ForEach(viewModel.anchors(in: day)) { anchor in
                        StopRow(anchor: anchor, viewModel: viewModel, openURL: openURL)
                    }
                } header: {
                    HStack {
                        Text("Day \(day.index + 1)")
                        Spacer()
                        if let url = viewModel.navigationURL(for: day) {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open Day in Maps", systemImage: "map")
                            }
                            .font(.footnote)
                        }
                    }
                }
            }
        }
        .navigationTitle("Summary")
    }

    private func dayHeader(_ day: TripDay) -> some View {
        HStack {
            Label(distanceText(day), systemImage: "arrow.triangle.turn.up.right.diamond")
            Spacer()
            Label(durationText(viewModel.drivingTime(in: day)), systemImage: "car")
            if viewModel.dwellTime(in: day) > 0 {
                Spacer()
                Label(durationText(viewModel.dwellTime(in: day)), systemImage: "figure.wave")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func distanceText(_ day: TripDay) -> String {
        String(format: "%.0f km", viewModel.distanceMeters(in: day) / 1000)
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

/// One stop in a day's summary: navigation hand-off, visited toggle, and an
/// inline comment/rating editor.
private struct StopRow: View {
    let anchor: RTPCore.Anchor
    let viewModel: SummaryViewModel
    let openURL: OpenURLAction

    @State private var comment: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    viewModel.toggleVisited(anchor)
                } label: {
                    Image(systemName: anchor.isVisited ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(anchor.isVisited ? .green : .secondary)
                }
                .buttonStyle(.plain)

                Text(anchor.title)
                    .strikethrough(anchor.isVisited)

                Spacer()

                Button {
                    openURL(viewModel.navigationURL(for: anchor))
                } label: {
                    Image(systemName: "map")
                }
                .buttonStyle(.plain)
            }

            RatingControl(rating: Binding(
                get: { anchor.rating },
                set: { viewModel.setRating($0, for: anchor) }
            ))

            TextField("Comment", text: $comment, axis: .vertical)
                .font(.footnote)
                .onAppear { comment = anchor.comment ?? "" }
                .onChange(of: comment) { _, newValue in
                    viewModel.setComment(newValue, for: anchor)
                }
        }
        .padding(.vertical, 2)
    }
}

/// A simple 0–5 star rating control.
private struct RatingControl: View {
    @Binding var rating: Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = (rating == star) ? nil : star
                } label: {
                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                        .font(.footnote)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
