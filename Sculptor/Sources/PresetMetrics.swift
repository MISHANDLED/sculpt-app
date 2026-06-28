import Foundation

/// Number of bands raised above flat (gain strictly greater than 0).
func bandsRaisedCount(_ gains: [Float]) -> Int {
    gains.filter { $0 > 0 }.count
}
