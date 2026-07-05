import CoreGraphics
import Foundation

/// Pure math for the 270° volume knob. Angle convention: degrees, 0 at
/// 12 o'clock, clockwise positive; the sweep runs -135°…+135° with the
/// gap centered at the bottom.
public enum KnobGeometry {
    public static let sweepDegrees: Float = 270
    private static let halfSweep: Float = 135

    /// Maps a clockwise-from-top angle to a 0…1 value. Angles inside the
    /// bottom gap clamp to the nearest sweep end (no wrap-around).
    public static func value(forAngle deg: Float) -> Float {
        let clamped = min(halfSweep, max(-halfSweep, deg))
        return (clamped + halfSweep) / sweepDegrees
    }

    /// Inverse of value(forAngle:), clamping the input to 0…1.
    public static func angle(forValue v: Float) -> Float {
        let clamped = min(1, max(0, v))
        return clamped * sweepDegrees - halfSweep
    }

    /// Fraction of the full circle the glow arc covers, for Circle().trim.
    public static func trimFraction(forValue v: Float) -> CGFloat {
        CGFloat(min(1, max(0, v))) * 0.75
    }

    /// Gesture-level latch: a real drag can never move more than ~0.5 in a
    /// single frame, so a jump bigger than that means the finger crossed the
    /// bottom gap and the raw angle wrapped (e.g. 0 -> 1). Hold the previous
    /// value in that case; tracking resumes once the new value is close again.
    /// Pass nil for the first sample of a gesture.
    public static func latchedValue(new: Float, previous: Float?) -> Float {
        guard let previous else { return new }
        return abs(new - previous) > 0.5 ? previous : new
    }

    /// Clockwise-from-top angle of a touch point around the knob center,
    /// in -180…180.
    public static func touchAngle(location: CGPoint, center: CGPoint) -> Float {
        let dx = Float(location.x - center.x)
        let dy = Float(location.y - center.y)
        return atan2(dx, -dy) * 180 / .pi
    }
}
