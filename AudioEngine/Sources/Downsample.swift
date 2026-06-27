import Foundation

/// Block-averages `samples` into exactly `count` contiguous blocks (the mean of
/// each block). `count` is clamped to >= 1. Empty input returns []. Input shorter
/// than `count` is returned unchanged.
public func downsample(_ samples: [Float], to count: Int) -> [Float] {
    let n = samples.count
    guard n > 0 else { return [] }
    let k = max(1, count)
    guard n > k else { return samples }
    var out = [Float](repeating: 0, count: k)
    for i in 0..<k {
        let lo = i * n / k
        let hi = (i + 1) * n / k
        let end = max(hi, lo + 1)
        var sum: Float = 0
        var c = 0
        for j in lo..<min(end, n) { sum += samples[j]; c += 1 }
        out[i] = c > 0 ? sum / Float(c) : 0
    }
    return out
}
