import Testing
@testable import Sculptor
import AudioEngine
import Foundation

@Suite struct SelectionPersistenceTests {
    @Test func builtinTokenRoundTrips() {
        for p in NoisePreset.allCases {
            let token = selectionToken(.builtin(p))
            #expect(token != nil)
            #expect(parseSelectionToken(token!) == .builtin(p))
        }
    }

    @Test func customTokenRoundTrips() {
        let id = UUID()
        let token = selectionToken(.custom(id))
        #expect(token != nil)
        #expect(parseSelectionToken(token!) == .custom(id))
    }

    @Test func noneHasNoToken() {
        #expect(selectionToken(.none) == nil)
    }

    @Test func malformedTokenParsesNil() {
        #expect(parseSelectionToken("garbage") == nil)
        #expect(parseSelectionToken("builtin:nope") == nil)
        #expect(parseSelectionToken("custom:not-a-uuid") == nil)
    }
}
