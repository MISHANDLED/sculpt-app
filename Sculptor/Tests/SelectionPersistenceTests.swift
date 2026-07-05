import Testing
@testable import Sculptor
import AudioEngine
import Foundation

@Suite struct SelectionPersistenceTests {
    @Test func builtinTokenRoundTrips() {
        for p in NoisePreset.allCases {
            let token = SelectionPersistence.token(.builtin(p))
            #expect(token != nil)
            #expect(SelectionPersistence.parse(token!) == .builtin(p))
        }
    }

    @Test func customTokenRoundTrips() {
        let id = UUID()
        let token = SelectionPersistence.token(.custom(id))
        #expect(token != nil)
        #expect(SelectionPersistence.parse(token!) == .custom(id))
    }

    @Test func noneHasNoToken() {
        #expect(SelectionPersistence.token(.none) == nil)
    }

    @Test func malformedTokenParsesNil() {
        #expect(SelectionPersistence.parse("garbage") == nil)
        #expect(SelectionPersistence.parse("builtin:nope") == nil)
        #expect(SelectionPersistence.parse("custom:not-a-uuid") == nil)
    }
}
