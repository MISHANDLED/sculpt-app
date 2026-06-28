import Testing
import SwiftData
import Foundation
@testable import Sculptor

@MainActor
@Suite struct CustomPresetTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CustomPreset.self, configurations: config)
        return ModelContext(container)
    }

    @Test func insertAndFetchRoundTrips() throws {
        let ctx = try makeContext()
        ctx.insert(CustomPreset(name: "Late night", gains: [1,2,3,4,5,6,7,8], sortIndex: 0))
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<CustomPreset>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Late night")
        #expect(fetched.first?.gains == [1,2,3,4,5,6,7,8])
    }

    @Test func fetchSortsBySortIndex() throws {
        let ctx = try makeContext()
        ctx.insert(CustomPreset(name: "B", gains: Array(repeating: 0, count: 8), sortIndex: 1))
        ctx.insert(CustomPreset(name: "A", gains: Array(repeating: 0, count: 8), sortIndex: 0))
        try ctx.save()
        let fetched = try ctx.fetch(
            FetchDescriptor<CustomPreset>(sortBy: [SortDescriptor(\.sortIndex)])
        )
        #expect(fetched.map(\.name) == ["A", "B"])
    }

    @Test func deleteRemovesPreset() throws {
        let ctx = try makeContext()
        let p = CustomPreset(name: "X", gains: Array(repeating: 0, count: 8), sortIndex: 0)
        ctx.insert(p)
        try ctx.save()
        ctx.delete(p)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<CustomPreset>()).isEmpty)
    }
}
