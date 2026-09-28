import Foundation

/// Incremental angles allow repeated turns and cross twelve o'clock without jumping.
public struct DialAdjustment {
    public private(set) var minutes: Double
    public private(set) var rotation: Double = 0
    private var lastAngle: Double?
    public init(minutes: Int) { self.minutes = Double(min(180, max(0, minutes))) }
    public var selectedMinutes: Int { Int(minutes.rounded()) }
    public mutating func turn(to angle: Double) {
        guard let previous = lastAngle else { lastAngle = angle; return }
        var delta = angle - previous
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        lastAngle = angle
        let next = min(180, max(0, minutes + delta / (.pi / 30)))
        rotation += (next - minutes) * 6
        minutes = next
    }
}

public struct PracticeTotal {
    public var value: String
    public var unit: String
    public init(seconds: Double) {
        let seconds = max(0, seconds)
        if seconds < 3600 { value = String(Int(seconds / 60)); unit = "total mins" }
        else {
            let divisor: Double = seconds < 86400 ? 3600 : 86400
            value = (seconds / divisor).formatted(.number.precision(.fractionLength(0...1)))
            unit = seconds < 86400 ? "total hours" : "total days"
        }
    }
}
