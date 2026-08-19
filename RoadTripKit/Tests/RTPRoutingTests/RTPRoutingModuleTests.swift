import Testing
@testable import RTPRouting

@Suite("RTPRouting module")
struct RTPRoutingModuleTests {
    @Test("Module loads independently of MapKit")
    func moduleName() {
        #expect(RTPRouting.moduleName == "RTPRouting")
    }
}
