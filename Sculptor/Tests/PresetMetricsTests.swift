import Testing
@testable import Sculptor

@Suite struct PresetMetricsTests {
    @Test func bandsRaisedCountsPositiveGains() {
        #expect(bandsRaisedCount([0, 0, 0, 0, 0, 0, 0, 0]) == 0)
        #expect(bandsRaisedCount([3, 0, 2, -1, 0, 5, 0, 0]) == 3)
        #expect(bandsRaisedCount([-1, -2, -3]) == 0)
    }

    @Test func copyNamePrefixesCopyOf() {
        #expect(copyName(of: "Late night") == "Copy of Late night")
    }

    @Test func sanitizedRenameTrimsWhitespace() {
        #expect(sanitizedRename(old: "Old", new: "  Hi  ") == "Hi")
    }

    @Test func sanitizedRenameEmptyRevertsToOld() {
        #expect(sanitizedRename(old: "Old", new: "   ") == "Old")
        #expect(sanitizedRename(old: "Old", new: "") == "Old")
    }
}
