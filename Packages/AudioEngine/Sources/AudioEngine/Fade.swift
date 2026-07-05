/// Linear fade curve from `start` down to 0 in `steps` equal decrements.
/// The final element is always exactly 0. Empty for steps <= 0.
func fadeCurve(from start: Float, steps: Int) -> [Float] {
    guard steps > 0 else { return [] }
    return (1...steps).map { start * Float(steps - $0) / Float(steps) }
}
