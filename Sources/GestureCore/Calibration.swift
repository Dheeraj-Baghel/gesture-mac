import Foundation

// Calibration samples the same palm anchor used for pointer movement. No
// clicking is necessary: hold a pointing pose at each comfortable corner.
public final class Calibration {
    public enum Stage: Equatable { case idle, upperLeft, lowerRight, complete }
    public private(set) var stage: Stage = .idle
    public private(set) var progress: Double = 0
    public private(set) var message = ""
    public private(set) var result: MappingArea?
    private var first: Point?
    private var anchor: Point?
    private var since: Double?
    private var samples: [Point] = []
    private var lastTime: Double?

    public init() {}
    public var inProgress: Bool { stage == .upperLeft || stage == .lowerRight }
    public func start() {
        stage = .upperLeft; first = nil; result = nil; lastTime = nil
        resetDwell()
        message = "Point at your comfortable UPPER-LEFT reach and hold still."
    }
    public func cancel() {
        stage = .idle; result = nil; first = nil; resetDwell()
        message = "Calibration cancelled. Previous range kept."
    }
    public func process(hand: Hand?, now: Double) {
        guard inProgress else { return }
        if let last = lastTime, now <= last { return }
        lastTime = now
        guard let hand = hand, hand.isReliable(), Gesture.classify(hand) == .point else {
            resetDwell()
            message = "Use one hand. Extend only your index finger."
            return
        }
        let p = hand.palmCenter
        if stage == .lowerRight, let first = first,
           p.x - first.x < 0.25 || first.y - p.y < 0.25 {
            resetDwell()
            message = "Move farther DOWN and RIGHT; leave a comfortable wide range."
            return
        }
        if let anchor = anchor, p.distance(to: anchor, aspect: hand.aspect) <= 0.03 {
            samples.append(p)
        } else {
            anchor = p; since = now; samples = [p]; progress = 0
        }
        progress = min(1, max(0, (now - (since ?? now)) / 1.1))
        message = stage == .upperLeft ? "Upper-left: hold still..." : "Lower-right: hold still..."
        guard progress >= 1, samples.count >= 8 else { return }
        let mean = Point(samples.map(\.x).reduce(0, +) / Double(samples.count),
                         samples.map(\.y).reduce(0, +) / Double(samples.count))
        if stage == .upperLeft {
            first = mean; stage = .lowerRight; resetDwell()
            message = "Now point at your comfortable LOWER-RIGHT reach and hold."
        } else if let first = first {
            let area = MappingArea(left: first.x, right: mean.x, bottom: mean.y, top: first.y)
            guard area.isValid else {
                resetDwell(); message = "Range is too small. Move farther down and right."; return
            }
            result = area; stage = .complete; progress = 1
            message = "Calibrated! Enable control when you are ready."
        }
    }
    private func resetDwell() { anchor = nil; since = nil; samples = []; progress = 0 }
}
