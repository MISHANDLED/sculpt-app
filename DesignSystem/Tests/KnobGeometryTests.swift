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

    @Test func touchAngleCardinalPoints() {
        let c = CGPoint(x: 100, y: 100)
        // straight up from center = 0°
        #expect(abs(KnobGeometry.touchAngle(location: CGPoint(x: 100, y: 40), center: c)) < 0.0001)
        // right = +90°, left = -90°
        #expect(abs(KnobGeometry.touchAngle(location: CGPoint(x: 160, y: 100), center: c) - 90) < 0.0001)
        #expect(abs(KnobGeometry.touchAngle(location: CGPoint(x: 40, y: 100), center: c) + 90) < 0.0001)
    }
}
