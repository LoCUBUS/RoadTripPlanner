import Testing
@testable import RTPCore

@Suite("Phase")
struct PhaseTests {
    @Test("Phases are ordered corridor < POIs < overnights < summary < journal")
    func phaseOrdering() {
        #expect(Phase.corridor < Phase.pointsOfInterest)
        #expect(Phase.pointsOfInterest < Phase.overnights)
        #expect(Phase.overnights < Phase.summary)
        #expect(Phase.summary < Phase.journal)
    }

    @Test("A fresh RevisionStamp does not need review")
    func freshStampDoesNotNeedReview() {
        let stamp = RevisionStamp()
        #expect(stamp.needsReview == false)
        #expect(stamp.lastRecalculatedAt == nil)
    }
}
