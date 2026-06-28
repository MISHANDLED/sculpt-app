import Foundation
import SwiftData

/// A user-saved EQ preset. Persisted with SwiftData.
@Model
final class CustomPreset {
    var id: UUID
    var name: String
    var gains: [Float]
    var sortIndex: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, gains: [Float], sortIndex: Int, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.gains = gains
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
