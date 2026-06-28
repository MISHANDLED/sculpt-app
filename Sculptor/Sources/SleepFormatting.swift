import Foundation

/// Zero-padded MM:SS for a countdown. Negative input clamps to "00:00".
func formatCountdown(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return String(format: "%02d:%02d", s / 60, s % 60)
}
