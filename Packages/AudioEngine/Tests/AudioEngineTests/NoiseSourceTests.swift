import Foundation
import Testing
@testable import AudioEngine

@Test func samplesStayInRange() {
    var s = NoiseSource(seed: 12345)
    for _ in 0..<10_000 {
        let v = s.next()
        #expect(v >= -1 && v <= 1)
    }
}

@Test func samplesAreNotConstant() {
    var s = NoiseSource(seed: 1)
    let first = s.next()
    var sawDifferent = false
    for _ in 0..<100 where s.next() != first { sawDifferent = true }
    #expect(sawDifferent)
}

@Test func differentSeedsDecorrelate() {
    var a = NoiseSource(seed: 0xAAAA)
    var b = NoiseSource(seed: 0x5555)
    var identical = 0
    for _ in 0..<1000 where a.next() == b.next() { identical += 1 }
    #expect(identical < 10)
}

@Test func zeroSeedDoesNotStall() {
    var s = NoiseSource(seed: 0)
    #expect(s.next() != s.next())
}

@Test func stereoNoiseIsCorrelatedButNotMono() {
    var source = StereoNoiseSource(leftSeed: 0xAAAA, rightSeed: 0x5555)
    var left: [Float] = []
    var right: [Float] = []
    left.reserveCapacity(10_000)
    right.reserveCapacity(10_000)

    for _ in 0..<10_000 {
        let sample = source.next()
        left.append(sample.left)
        right.append(sample.right)
    }

    let crossProduct = zip(left, right).reduce(Float.zero) {
        $0 + $1.0 * $1.1
    }
    let leftEnergy = left.reduce(Float.zero) { $0 + $1 * $1 }
    let rightEnergy = right.reduce(Float.zero) { $0 + $1 * $1 }
    let correlation = crossProduct / sqrt(leftEnergy * rightEnergy)

    #expect(correlation > 0.55)
    #expect(correlation < 0.8)
    #expect(zip(left, right).contains { $0 != $1 })
}
