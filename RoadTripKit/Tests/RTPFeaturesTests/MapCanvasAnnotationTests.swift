import Foundation
import Testing
import RTPCore
@testable import RTPFeatures

@Suite("MapCanvasAnnotation")
struct MapCanvasAnnotationTests {
    @Test("Anchor kinds map to the expected annotation style and symbol")
    func anchorKindMapsToStyle() {
        let cases: [(AnchorKind, MapCanvasAnnotation.Style)] = [
            (.start, .start),
            (.destination, .destination),
            (.waypoint, .waypoint),
            (.poi, .poi),
            (.lodging, .lodging)
        ]

        for (kind, expectedStyle) in cases {
            let anchor = Anchor(kind: kind, title: "Test")
            let annotation = MapCanvasAnnotation(anchor: anchor)
            #expect(annotation.style == expectedStyle)
            #expect(annotation.id == anchor.id)
            #expect(annotation.title == "Test")
        }
    }

    @Test("Every style has a distinct, non-empty SF Symbol")
    func stylesHaveDistinctSymbols() {
        let styles: [MapCanvasAnnotation.Style] = [.start, .destination, .waypoint, .poi, .lodging, .searchResult, .timeUp, .photo]
        let symbols = styles.map(\.systemImage)
        #expect(symbols.allSatisfy { !$0.isEmpty })
        #expect(Set(symbols).count == symbols.count)
    }

    @Test("Every style has a distinct, non-empty accessibility description")
    func stylesHaveDistinctAccessibilityDescriptions() {
        let styles: [MapCanvasAnnotation.Style] = [.start, .destination, .waypoint, .poi, .lodging, .searchResult, .timeUp, .photo]
        let descriptions = styles.map(\.accessibilityDescription)
        #expect(descriptions.allSatisfy { !$0.isEmpty })
        #expect(Set(descriptions).count == descriptions.count)
    }
}
