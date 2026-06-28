import Foundation

/// Number of bands raised above flat (gain strictly greater than 0).
func bandsRaisedCount(_ gains: [Float]) -> Int {
    gains.filter { $0 > 0 }.count
}

/// Name for a duplicated preset.
func copyName(of name: String) -> String {
    "Copy of \(name)"
}

/// Resolves a rename submission: trimmed; an empty result reverts to the old name.
func sanitizedRename(old: String, new: String) -> String {
    let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? old : trimmed
}
