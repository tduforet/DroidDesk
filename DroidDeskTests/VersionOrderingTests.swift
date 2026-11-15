import Testing
@testable import DroidDesk

struct VersionOrderingTests {
    @Test func comparesNumbersNotText() {
        #expect(VersionOrdering.isOlder("9.0.0", than: "10.0.0"))
        #expect(!VersionOrdering.isOlder("10.0.0", than: "9.0.0"))
    }
}
