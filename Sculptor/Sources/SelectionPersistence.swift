import AudioEngine
import Foundation

/// Stable string token for persisting the active selection. nil for `.none`.
func selectionToken(_ selection: PresetSelection) -> String? {
    switch selection {
    case .none:           return nil
    case .builtin(let p): return "builtin:\(builtinKey(p))"
    case .custom(let id): return "custom:\(id.uuidString)"
    }
}

/// Parses a token back to a selection. nil if malformed/unknown.
func parseSelectionToken(_ token: String) -> PresetSelection? {
    if token.hasPrefix("builtin:") {
        let key = String(token.dropFirst("builtin:".count))
        return builtinFromKey(key).map { PresetSelection.builtin($0) }
    }
    if token.hasPrefix("custom:") {
        let raw = String(token.dropFirst("custom:".count))
        if let id = UUID(uuidString: raw) { return .custom(id) }
    }
    return nil
}

private func builtinKey(_ p: NoisePreset) -> String {
    switch p {
    case .white:         return "white"
    case .pink:          return "pink"
    case .brown:         return "brown"
    case .grey:          return "grey"
    case .speechBlocker: return "speechBlocker"
    }
}

private func builtinFromKey(_ key: String) -> NoisePreset? {
    switch key {
    case "white":         return .white
    case "pink":          return .pink
    case "brown":         return .brown
    case "grey":          return .grey
    case "speechBlocker": return .speechBlocker
    default:              return nil
    }
}
