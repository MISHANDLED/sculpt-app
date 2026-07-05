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
