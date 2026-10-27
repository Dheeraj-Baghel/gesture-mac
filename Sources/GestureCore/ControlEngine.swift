import Foundation

// Pure state machine. No camera, permissions, or actual mouse events in this
// module; tests use deterministic timestamps and synthetic landmark samples.
public enum Action: Equatable {
    case move(Point)
    case leftDown(Point)
    case leftUp(Point)
    case rightClick(Point)
    case scroll(Int)
}

public enum TrackingIssue: String {
    case missing = "No hand detected"
    case multiple = "Use one hand only"
    case unreliable = "Move into better light"
    case stale = "Tracking interrupted"
}

public struct EngineOutput {
    public var actions: [Action] = []
    public var gesture: Gesture = .unknown
    public var message: String = "Preview only"
    public var fistProgress: Double = 0
    public var enabled = false
    public var paused = true
    public var pointer: Point?
    public init() {}
}

public final class ControlEngine {
    public var settings: Settings
    public private(set) var enabled = false
    public private(set) var paused = true
    public private(set) var pointer: Point?
    public private(set) var lastGesture: Gesture = .unknown
    private var lastFrame: Double?
    private var lastGoodFrame: Double?
    private var pointerReady = false
    private var neutralSince: Double?
    private var fistSince: Double?
    private var fistConsumed = false
    private var fistReleaseSince: Double?
    private var pinchSince: Double?
    private var buttonDown = false
    private var pinchAnchor: Point?
    private var pinchPointer: Point?
    private var rightSince: Double?
    private var rightConsumed = false
    private var scrollAnchor: Double?
    private var scrollRemainder: Double = 0
    private var lastMoveTime: Double?
    private var status = "Preview only"

    public init(settings: Settings = Settings()) { self.settings = settings }

    @discardableResult
    public func enable(now: Double) -> EngineOutput {
        let actions = clearInteraction()
        enabled = true; paused = false
        lastFrame = now; lastGoodFrame = now
        status = "Point with one finger to begin"
        resetFist()
        return output(actions)
    }

    @discardableResult
    public func disable(reason: String = "Preview only") -> EngineOutput {
        let actions = clearInteraction()
        enabled = false; paused = true; status = reason
        resetFist()
        return output(actions)
    }

    @discardableResult
    public func pause(reason: String = "Paused") -> EngineOutput {
        let actions = clearInteraction()
        paused = true; status = reason
        return output(actions)
    }

    @discardableResult
    public func resume(now: Double) -> EngineOutput {
        guard enabled else { return output() }
        let actions = clearInteraction()
        paused = false; lastFrame = now; lastGoodFrame = now
        status = "Point with one finger to begin"
        return output(actions)
    }

    public func tick(now: Double) -> EngineOutput {
        guard enabled, !paused, let last = lastGoodFrame, now - last > 0.75 else {
            return output()
        }
        return pause(reason: "Tracking lost. Hold a fist to resume.")
    }

    public func process(hand: Hand?, now: Double,
                        issue: TrackingIssue = .missing) -> EngineOutput {
        // Reject non-monotonic frames: they must not revive a finished pinch.
        if let last = lastFrame, now < last { return output() }
        lastFrame = now
        guard let hand = hand, hand.isReliable() else {
            var actions = clearInteraction()
            resetFist()
            lastGesture = .unknown
            status = hand == nil ? issue.rawValue : TrackingIssue.unreliable.rawValue
            if enabled, !paused, let last = lastGoodFrame, now - last > 0.75 {
                let result = pause(reason: "Tracking lost. Hold a fist to resume.")
                actions += result.actions
            }
            return output(actions)
        }
        lastGoodFrame = now
        let gesture = Gesture.classify(hand, previous: lastGesture)
        let previousGesture = lastGesture
        lastGesture = gesture
        var actions: [Action] = []
        var fistProgress: Double = 0

        if gesture == .fist {
            actions += clearInteraction()
            fistReleaseSince = nil
            if enabled && !fistConsumed {
                if fistSince == nil { fistSince = now }
                fistProgress = min(1, max(0, (now - (fistSince ?? now)) / 0.7))
                if fistProgress >= 1 {
                    fistConsumed = true
                    if paused {
                        paused = false
                        status = "Resumed. Point with one finger."
                    } else {
                        paused = true
                        status = "Paused. Hold a fist again to resume."
                    }
                } else { status = paused ? "Hold fist to resume..." : "Hold fist to pause..." }
            } else if !enabled { status = "Preview only - controls disabled" }
            return output(actions, fistProgress: fistProgress)
        } else {
            fistSince = nil
            if fistConsumed {
                if fistReleaseSince == nil { fistReleaseSince = now }
                if now - (fistReleaseSince ?? now) >= 0.18 { resetFist() }
            }
        }

        guard enabled && !paused else {
            status = enabled ? "Paused - hold a fist to resume" : "Preview only - controls disabled"
            return output()
        }
        // No action on a pinched hand at startup or after loss. A deliberate
        // neutral pointing pose must first be held for 250 ms.
        if !pointerReady {
            if gesture == .point {
                if neutralSince == nil { neutralSince = now }
                if now - (neutralSince ?? now) >= 0.25 {
                    pointerReady = true
                    pointer = settings.area.map(hand.palmCenter)
                    lastMoveTime = now
                    status = "Pointer ready"
                    actions.append(.move(pointer!))
                } else { status = "Hold your pointing pose..." }
            } else {
                neutralSince = nil
                status = "Point with one finger to begin"
            }
            return output(actions)
        }

        if gesture != .indexPinch {
            if buttonDown, let p = pointer { actions.append(.leftUp(p)) }
            buttonDown = false; pinchSince = nil
            pinchAnchor = nil; pinchPointer = nil
        }
        if gesture != .middlePinch { rightSince = nil; rightConsumed = false }
        if gesture != .scroll { scrollAnchor = nil; scrollRemainder = 0 }

        switch gesture {
        case .point:
            let p = smoothed(settings.area.map(hand.palmCenter), now: now)
            actions.append(.move(p))
            status = "Move your hand to move the pointer"
        case .indexPinch:
            if pinchSince == nil {
                pinchSince = now
                pinchAnchor = settings.area.map(hand.palmCenter)
                pinchPointer = pointer
            }
            let held = now - (pinchSince ?? now)
            if held >= 0.09 && !buttonDown, let p = pointer {
                buttonDown = true; actions.append(.leftDown(p))
            }
            // Freeze the cursor during tap pinches. Only a sustained pinch
            // becomes a drag, mapped relative to the pinch-start position.
            if held >= 0.38, buttonDown, let a = pinchAnchor, let p = pinchPointer {
                let raw = settings.area.map(hand.palmCenter)
                let target = Point(p.x + raw.x - a.x, p.y + raw.y - a.y).clamped()
                actions.append(.move(smoothed(target, now: now)))
                status = "Dragging - separate thumb and index to release"
            } else { status = "Pinch to click; hold to drag" }
        case .middlePinch:
            if settings.rightClickEnabled {
                if rightSince == nil { rightSince = now }
                if now - (rightSince ?? now) >= 0.15 && !rightConsumed, let p = pointer {
                    actions.append(.rightClick(p)); rightConsumed = true
                }
                status = "Right click - release to repeat"
            } else { status = "Right click is disabled" }
        case .scroll:
            let y = hand.palmCenter.y
            // Freeze mouse position in scroll mode and reset on every entry.
            if previousGesture == .scroll, let anchor = scrollAnchor {
                let delta = y - anchor
                if abs(delta) > 0.0025 {
                    let sign = settings.naturalScrolling ? -1.0 : 1.0
                    scrollRemainder += delta * settings.scrollSensitivity * sign
                    let pixels = Int(scrollRemainder.rounded(.towardZero))
                    if pixels != 0 {
                        let bounded = max(-60, min(60, pixels))
                        actions.append(.scroll(bounded))
                        scrollRemainder -= Double(bounded)
                        // Discard excess after a large tracking jump.
                        scrollRemainder = max(-1, min(1, scrollRemainder))
                    }
                    scrollAnchor = y
                }
            } else { scrollAnchor = y; scrollRemainder = 0 }
            status = "Move two fingers up / down to scroll"
        case .openPalm, .unknown:
            // Ambiguous/resting poses never click or move the cursor. A fresh
            // pointing hold is required before another pinch can act.
            actions += clearInteraction()
            status = "Resting - point to continue"
        case .fist: break
        }
        return output(actions)
    }

    private func smoothed(_ target: Point, now: Double) -> Point {
        guard let old = pointer else { pointer = target; lastMoveTime = now; return target }
        let dt = min(0.1, max(0, now - (lastMoveTime ?? now)))
        lastMoveTime = now
        let alpha = 1 - exp(-dt / max(0.02, settings.smoothingSeconds))
        let p = Point(old.x + (target.x - old.x) * alpha,
                      old.y + (target.y - old.y) * alpha).clamped()
        pointer = p
        return p
    }

    private func clearInteraction() -> [Action] {
        var actions: [Action] = []
        if buttonDown, let p = pointer { actions.append(.leftUp(p)) }
        buttonDown = false; pinchSince = nil; pinchAnchor = nil; pinchPointer = nil
        rightSince = nil; rightConsumed = false
        scrollAnchor = nil; scrollRemainder = 0
        pointerReady = false; neutralSince = nil; lastMoveTime = nil
        return actions
    }
    private func resetFist() {
        fistSince = nil; fistConsumed = false; fistReleaseSince = nil
    }
    private func output(_ actions: [Action] = [], fistProgress: Double = 0) -> EngineOutput {
        var result = EngineOutput()
        result.actions = actions; result.gesture = lastGesture; result.message = status
        result.enabled = enabled; result.paused = paused
        result.pointer = pointer; result.fistProgress = fistProgress
        return result
    }
}
