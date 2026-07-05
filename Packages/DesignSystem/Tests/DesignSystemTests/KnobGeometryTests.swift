import Testing
import CoreGraphics
@testable import DesignSystem

@Suite("Knob geometry")
struct KnobGeometryTests {
    @Test func sweepEndsMapToZeroAndOne() {
        #expect(KnobGeometry.value(forAngle: -135) == 0)
        #expect(KnobGeometry.value(forAngle: 135) == 1)
    }

    @Test func topOfDialIsHalf() {
        #expect(abs(KnobGeometry.value(forAngle: 0) - 0.5) < 0.0001)
    }

    @Test func gapAnglesClampToNearestEnd() {
        #expect(KnobGeometry.value(forAngle: 170) == 1)   // past end, in gap
        #expect(KnobGeometry.value(forAngle: -170) == 0)  // before start, in gap
        #expect(KnobGeometry.value(forAngle: 180) == 1)   // dead bottom counts as high side
    }

    @Test func angleForValueRoundTrips() {
        #expect(KnobGeometry.angle(forValue: 0) == -135)
        #expect(KnobGeometry.angle(forValue: 1) == 135)
        #expect(abs(KnobGeometry.angle(forValue: 0.5)) < 0.0001)
        #expect(KnobGeometry.angle(forValue: -0.5) == -135) // clamps input
        #expect(KnobGeometry.angle(forValue: 2) == 135)
    }

    @Test func trimFractionIsThreeQuartersOfValue() {
        #expect(KnobGeometry.trimFraction(forValue: 0) == 0)
        #expect(KnobGeometry.trimFraction(forValue: 0.5) == 0.375)
        #expect(KnobGeometry.trimFraction(forValue: 1) == 0.75)
    }

    @Test func latchHoldsMinAcrossBottomGap() {
        // Finger drifts past the 0-end through dead bottom: raw value flips
        // 0 -> 1 in one frame. Latch must keep 0 (spec: never wrap 0 -> 100).
        #expect(KnobGeometry.latchedValue(new: 1, previous: 0) == 0)
    }

    @Test func latchHoldsMaxAcrossBottomGap() {
        #expect(KnobGeometry.latchedValue(new: 0, previous: 1) == 1)
    }

    @Test func latchReleasesOnNormalResume() {
        // Finger swings back around through the arc: tracking resumes.
        #expect(KnobGeometry.latchedValue(new: 0.3, previous: 0) == 0.3)
        #expect(KnobGeometry.latchedValue(new: 0.7, previous: 1) == 0.7)
    }

    @Test func latchPassesThroughWithoutPrevious() {
        // First touch of a gesture: no previous sample, take the new value.
        #expect(KnobGeometry.latchedValue(new: 1, previous: nil) == 1)
        #expect(KnobGeometry.latchedValue(new: 0.42, previous: nil) == 0.42)
    }

    @Test func latchPassesSmallDeltasAnywhere() {
        #expect(KnobGeometry.latchedValue(new: 0.6, previous: 0.5) == 0.6)
        #expect(KnobGeometry.latchedValue(new: 0.45, previous: 0.9) == 0.45)
        #expect(KnobGeometry.latchedValue(new: 0.5, previous: 0) == 0.5)
    }

    @Test func latchBlocksImpossibleJumpFromMidArc() {
        // >0.5 jump in one frame is impossible for a real drag; treat as
        // gap-cross noise and hold the previous value.
        #expect(KnobGeometry.latchedValue(new: 1, previous: 0.4) == 0.4)
    }

    @Test func touchAngleCardinalPoints() {
        let c = CGPoint(x: 100, y: 100)
        // straight up from center = 0°
        #expect(abs(KnobGeometry.touchAngle(location: CGPoint(x: 100, y: 40), center: c)) < 0.0001)
        // right = +90°, left = -90°
        #expect(abs(KnobGeometry.touchAngle(location: CGPoint(x: 160, y: 100), center: c) - 90) < 0.0001)
        #expect(abs(KnobGeometry.touchAngle(location: CGPoint(x: 40, y: 100), center: c) + 90) < 0.0001)
    }
}
