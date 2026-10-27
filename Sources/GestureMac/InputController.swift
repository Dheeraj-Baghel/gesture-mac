import AppKit
import ApplicationServices
import GestureCore

// This is the only file that posts synthetic input. All actions are permission
// gated, main-thread serialized, and directed at a user-selected display.
final class InputController {
    private(set) var leftHeld = false
    private(set) var lastLocation: CGPoint?
    var displayID = CGMainDisplayID()
    var dryRun = false
    private let source = CGEventSource(stateID: .hidSystemState)
    private(set) var postedEvents = 0

    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func apply(_ actions: [Action]) {
        precondition(Thread.isMainThread)
        guard !dryRun else { return }
        // Always attempt to release an outstanding button on revocation. The
        // OS may reject it, but retaining internal down-state would be worse.
        guard Self.trusted, CGDisplayIsOnline(displayID) != 0,
              CGDisplayIsAsleep(displayID) == 0 else { releaseAll(); return }
        for action in actions {
            switch action {
            case .move(let p):
                let location = screenPoint(p)
                mouse(leftHeld ? .leftMouseDragged : .mouseMoved, at: location, button: .left)
                lastLocation = location
            case .leftDown(let p):
                guard !leftHeld else { continue }
                let location = screenPoint(p)
                mouse(.leftMouseDown, at: location, button: .left)
                leftHeld = true; lastLocation = location
            case .leftUp:
                if leftHeld { releaseAll() }
            case .rightClick(let p):
                guard !leftHeld else { continue }
                let location = screenPoint(p)
                mouse(.rightMouseDown, at: location, button: .right)
                mouse(.rightMouseUp, at: location, button: .right)
                lastLocation = location
            case .scroll(let pixels):
                guard !leftHeld, pixels != 0 else { continue }
                if let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                                       wheelCount: 1, wheel1: Int32(pixels), wheel2: 0, wheel3: 0) {
                    event.post(tap: .cghidEventTap); postedEvents += 1
                }
            }
        }
    }

    func releaseAll() {
        precondition(Thread.isMainThread)
        if leftHeld && !dryRun {
            let location = CGEvent(source: nil)?.location ?? lastLocation ?? .zero
            mouse(.leftMouseUp, at: location, button: .left)
        }
        leftHeld = false
    }

    func screenPoint(_ normalized: Point) -> CGPoint {
        let p = normalized.clamped()
        // CGDisplayBounds and CGEvent share the same global top-left coordinate
        // convention; avoid mixing these with NSScreen's bottom-left frames.
        let rect = CGDisplayBounds(displayID)
        return CGPoint(x: rect.minX + p.x * max(1, rect.width - 1),
                       y: rect.minY + p.y * max(1, rect.height - 1))
    }
    private func mouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        if let event = CGEvent(mouseEventSource: source, mouseType: type,
                               mouseCursorPosition: point, mouseButton: button) {
            if type == .leftMouseDown || type == .leftMouseUp || type == .rightMouseDown || type == .rightMouseUp {
                event.setIntegerValueField(.mouseEventClickState, value: 1)
            }
            event.post(tap: .cghidEventTap); postedEvents += 1
        }
    }
}
