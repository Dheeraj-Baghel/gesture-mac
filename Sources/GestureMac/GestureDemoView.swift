import AppKit

// A purpose-built vector teaching illustration, not captured video and not a
// recognition fixture. The sample cursor is drawn into this view only.
enum DemoGesture: Int, CaseIterable {
    case move, click, drag, scroll, rightClick, pause
    var fileName: String { ["move", "click", "drag", "scroll", "right-click", "pause"][rawValue] }
    var title: String {
        ["01  Move the pointer", "02  Pinch to click", "03  Hold a pinch to drag",
         "04  Two fingers to scroll", "05  Right-click", "06  Fist to pause / resume"][rawValue]
    }
    var instructions: String {
        switch self {
        case .move: return "Extend your index finger, curl the other three fingers, and move your whole hand. Either hand works."
        case .click: return "With the other fingers curled, touch thumb and index fingertips for at least 0.09 seconds. Separate to release."
        case .drag: return "Pinch thumb + index and hold for 0.38 seconds. Move while pinched; separate your fingertips to drop."
        case .scroll: return "Extend index + middle, curl ring + little, then move your whole hand up or down. The pointer stays still."
        case .rightClick: return "Keep index extended. Curl ring + little and pinch thumb + middle for 0.15 seconds. Release before repeating."
        case .pause: return "Close all four fingers into a fist and hold for 0.7 seconds. Release the fist, then repeat to resume."
        }
    }
    var duration: Double {
        switch self {
        case .move: return 4
        case .click, .rightClick: return 3
        case .drag: return 5
        case .scroll: return 4
        case .pause: return 4
        }
    }
    func caption(at phase: Double) -> String {
        let p = min(1, max(0, phase))
        switch self {
        case .move: return "Move your whole hand; the palm anchor steers the pointer."
        case .click:
            if p < 0.25 { return "1. Point at the target." }
            if p < 0.68 { return "2. Touch thumb + index; the pointer stays steady." }
            return "3. Separate your fingertips to complete the click."
        case .drag:
            if p < 0.24 { return "1. Pinch and hold for 0.38 seconds." }
            if p < 0.76 { return "2. Keep pinching while moving your hand." }
            return "3. Separate your fingertips to drop the item."
        case .scroll: return "Keep two fingers raised. Hand up/down scrolls; it does not move the pointer."
        case .rightClick:
            if p < 0.25 { return "1. Keep index up; bring thumb toward middle." }
            if p < 0.68 { return "2. Touch thumb + middle for 0.15 seconds." }
            return "3. Release before another right-click."
        case .pause:
            if p < 0.27 { return "1. Close all four fingers into a fist." }
            if p < 0.445 { return "2. Hold the fist for 0.7 seconds." }
            if p < 0.86 { return "3. Paused. Keeping the fist closed will not toggle again." }
            return "4. Release the fist; repeat the hold to resume."
        }
    }
}

final class GestureDemoView: NSView {
    var gesture: DemoGesture = .move { didSet { needsDisplay = true } }
    var phase: Double = 0 { didSet { needsDisplay = true } }
    private let mint = NSColor(calibratedRed: 0.57, green: 0.88, blue: 0.74, alpha: 1)
    private let gold = NSColor(calibratedRed: 1, green: 0.76, blue: 0.36, alpha: 1)
    private let ink = NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.12, alpha: 1)
    override var isOpaque: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 720, height: 310) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Animated hand illustration and a simulated pointer. No actual Mac input.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func draw(_ dirtyRect: NSRect) {
        ink.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        let p = min(1, max(0, phase))
        label("SAMPLE HAND", at: NSPoint(x: 20, y: bounds.height - 29), size: 10, color: .white.withAlphaComponent(0.65))
        label("SAMPLE RESULT - NOT YOUR MAC", at: NSPoint(x: bounds.width * 0.53, y: bounds.height - 29), size: 10, color: .white.withAlphaComponent(0.65))
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.width * 0.49, y: 28))
        separator.line(to: NSPoint(x: bounds.width * 0.49, y: bounds.height - 45))
        NSColor.white.withAlphaComponent(0.12).setStroke(); separator.stroke()
        var offset = NSPoint.zero
        if gesture == .move {
            offset = NSPoint(x: sin(p * 2 * .pi) * 18, y: cos(p * 2 * .pi) * 9)
        } else if gesture == .scroll {
            offset.y = sin(p * 2 * .pi) * 20
        } else if gesture == .drag {
            offset.x = ramp(p, 0.24, 0.76) * 35 - 17
        }
        let handWidth = min(bounds.width * 0.39, 245)
        let handRect = NSRect(x: bounds.width * 0.23 - handWidth / 2 + offset.x,
                              y: 12 + offset.y, width: handWidth, height: 245)
        let contact: Double
        if gesture == .click || gesture == .rightClick {
            contact = ramp(p, 0.18, 0.32) * (1 - ramp(p, 0.65, 0.79))
        } else if gesture == .drag {
            contact = ramp(p, 0.03, 0.12) * (1 - ramp(p, 0.76, 0.85))
        } else { contact = 0 }
        let fist = gesture == .pause ? ramp(p, 0.10, 0.27) * (1 - ramp(p, 0.86, 0.97)) : 0
        drawHand(in: handRect, contact: contact, fist: fist)
        if gesture == .move || gesture == .drag {
            arrow(from: NSPoint(x: 28, y: 124), to: NSPoint(x: 70, y: 124), color: mint)
            arrow(from: NSPoint(x: 70, y: 124), to: NSPoint(x: 28, y: 124), color: mint)
        } else if gesture == .scroll {
            arrow(from: NSPoint(x: 42, y: 90), to: NSPoint(x: 42, y: 180), color: mint)
            arrow(from: NSPoint(x: 42, y: 180), to: NSPoint(x: 42, y: 90), color: mint)
        }
        drawResult(phase: p, contact: contact)
        let timeline = NSRect(x: 20, y: 9, width: bounds.width - 40, height: 3)
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: timeline, xRadius: 1.5, yRadius: 1.5).fill()
        mint.setFill()
        NSBezierPath(roundedRect: NSRect(x: timeline.minX, y: timeline.minY, width: timeline.width * p, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    }

    private func drawHand(in rect: NSRect, contact: Double, fist: Double) {
        func pos(_ x: Double, _ y: Double) -> NSPoint {
            NSPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func blend(_ a: NSPoint, _ b: NSPoint, _ t: Double) -> NSPoint {
            NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        // Palm and wrist establish a recognizable hand, not just a stick figure.
        let palm = NSBezierPath()
        palm.move(to: pos(0.34, 0.11)); palm.line(to: pos(0.32, 0.29))
        palm.curve(to: pos(0.25, 0.46), controlPoint1: pos(0.22, 0.32), controlPoint2: pos(0.22, 0.40))
        palm.curve(to: pos(0.36, 0.58), controlPoint1: pos(0.27, 0.55), controlPoint2: pos(0.30, 0.58))
        palm.line(to: pos(0.64, 0.57))
        palm.curve(to: pos(0.72, 0.48), controlPoint1: pos(0.70, 0.57), controlPoint2: pos(0.72, 0.54))
        palm.curve(to: pos(0.62, 0.28), controlPoint1: pos(0.73, 0.38), controlPoint2: pos(0.67, 0.30))
        palm.line(to: pos(0.62, 0.11)); palm.close()
        mint.setFill(); palm.fill()
        let bases: [NSPoint] = [pos(0.35, 0.54), pos(0.48, 0.56), pos(0.60, 0.54), pos(0.70, 0.50)]
        let tips: [NSPoint] = [pos(0.31, 0.96), pos(0.48, 1.02), pos(0.65, 0.94), pos(0.81, 0.82)]
        for i in 0..<4 {
            let extended = i == 0 || (i == 1 && gesture == .scroll)
            var curl = extended ? fist : 1.0
            if gesture == .pause { curl = fist }
            var points = [bases[i],
                          blend(pos(0.35 + Double(i) * 0.12, 0.76), pos(0.35 + Double(i) * 0.12, 0.66), curl),
                          blend(pos(0.33 + Double(i) * 0.14, 0.88), pos(0.37 + Double(i) * 0.12, 0.60), curl),
                          blend(tips[i], pos(0.36 + Double(i) * 0.12, 0.49), curl)]
            if (gesture == .click || gesture == .drag) && i == 0 {
                let pinched = [bases[i], pos(0.34, 0.76), pos(0.22, 0.79), pos(0.22, 0.68)]
                points = zip(points, pinched).map { blend($0.0, $0.1, contact) }
            }
            if gesture == .rightClick && i == 1 {
                let pinched = [bases[i], pos(0.48, 0.77), pos(0.39, 0.81), pos(0.28, 0.70)]
                // Middle finger opens toward the pinch instead of showing a
                // different (two-finger-scroll) pose during the approach.
                let approached = [bases[i], pos(0.48, 0.68), pos(0.43, 0.68), pos(0.39, 0.60)]
                points = zip(approached, pinched).map { blend($0.0, $0.1, contact) }
            }
            tube(points, width: i == 3 ? 19 : 23, color: (contact > 0.8 && ((i == 0 && gesture != .rightClick) || (i == 1 && gesture == .rightClick))) ? gold : mint)
            // Fingernail makes the direction of the curled fingertip legible.
            if let tip = points.last {
                let nail = NSBezierPath(roundedRect: NSRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 8), xRadius: 3, yRadius: 3)
                ink.withAlphaComponent(0.20).setFill(); nail.fill()
            }
        }
        let relaxedThumb = [pos(0.29, 0.35), pos(0.15, 0.43), pos(0.10, 0.53), pos(0.07, 0.59)]
        let tip = gesture == .rightClick ? pos(0.28, 0.70) : pos(0.22, 0.68)
        let pinchedThumb = [pos(0.29, 0.35), pos(0.13, 0.44), pos(0.10, 0.60), tip]
        let fistThumb = [pos(0.29, 0.35), pos(0.30, 0.44), pos(0.43, 0.48), pos(0.57, 0.46)]
        var thumb = zip(relaxedThumb, pinchedThumb).map { blend($0.0, $0.1, contact) }
        thumb = zip(thumb, fistThumb).map { blend($0.0, $0.1, fist) }
        tube(thumb, width: 24, color: contact > 0.8 ? gold : mint)
        // Palm crease and wrist cuff remain still as fingertips articulate.
        let crease = NSBezierPath()
        crease.move(to: pos(0.34, 0.32))
        crease.curve(to: pos(0.60, 0.40), controlPoint1: pos(0.43, 0.39), controlPoint2: pos(0.52, 0.42))
        crease.lineWidth = 2; ink.withAlphaComponent(0.25).setStroke(); crease.stroke()
        if contact > 0.85 {
            let ring = NSBezierPath(ovalIn: NSRect(x: tip.x - 17, y: tip.y - 17, width: 34, height: 34))
            ring.lineWidth = 2; gold.withAlphaComponent(0.7).setStroke(); ring.stroke()
        }
    }

    private func drawResult(phase p: Double, contact: Double) {
        let r = NSRect(x: bounds.width * 0.53, y: 54, width: bounds.width * 0.43, height: 201)
        let paper = NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.90, alpha: 1)
        paper.setFill(); NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).fill()
        let chrome = NSRect(x: r.minX, y: r.maxY - 26, width: r.width, height: 26)
        ink.withAlphaComponent(0.08).setFill(); NSBezierPath(rect: chrome).fill()
        for i in 0..<3 {
            ink.withAlphaComponent(0.25).setFill()
            NSBezierPath(ovalIn: NSRect(x: r.minX + 13 + Double(i) * 13, y: chrome.midY - 3, width: 6, height: 6)).fill()
        }
        var cursor = NSPoint(x: r.midX, y: r.midY - 12)
        switch gesture {
        case .move:
            cursor.x += sin(p * 2 * .pi) * 75
            cursor.y += cos(p * 2 * .pi) * 35
            label("Pointer follows your hand", at: NSPoint(x: r.minX + 16, y: r.minY + 15), size: 11, color: ink)
        case .click, .rightClick:
            let target = NSRect(x: r.midX - 66, y: r.midY - 24, width: 132, height: 38)
            (contact > 0.85 ? mint : NSColor.white).setFill()
            NSBezierPath(roundedRect: target, xRadius: 8, yRadius: 8).fill()
            label(gesture == .click ? "Click target" : "Right-click target", at: NSPoint(x: target.minX + 13, y: target.midY - 5), size: 12, color: ink)
            cursor = NSPoint(x: target.midX + 23, y: target.midY - 5)
            if gesture == .rightClick && p > 0.38 && p < 0.92 {
                let menu = NSRect(x: cursor.x + 3, y: cursor.y - 67, width: 112, height: 63)
                NSColor.white.setFill(); NSBezierPath(roundedRect: menu, xRadius: 7, yRadius: 7).fill()
                label("Open", at: NSPoint(x: menu.minX + 11, y: menu.maxY - 22), size: 11, color: ink)
                label("Show info", at: NSPoint(x: menu.minX + 11, y: menu.maxY - 45), size: 11, color: ink)
            }
            label(contact > 0.85 ? "Fingertips touching" : "Separate to release", at: NSPoint(x: r.minX + 16, y: r.minY + 15), size: 11, color: ink)
        case .drag:
            let movement = ramp(p, 0.24, 0.76) * (r.width - 130)
            let item = NSRect(x: r.minX + 28 + movement, y: r.midY - 25, width: 72, height: 57)
            (contact > 0.85 ? gold : mint).setFill()
            NSBezierPath(roundedRect: item, xRadius: 9, yRadius: 9).fill()
            label("ITEM", at: NSPoint(x: item.minX + 19, y: item.midY - 4), size: 10, color: ink)
            cursor = NSPoint(x: item.midX, y: item.midY)
            label(p > 0.85 ? "Dropped" : p > 0.24 ? "Hold + move" : "Hold 0.38 seconds", at: NSPoint(x: r.minX + 16, y: r.minY + 15), size: 11, color: ink)
        case .scroll:
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: r.minX + 10, y: r.minY + 40, width: r.width - 20, height: 128)).addClip()
            let offset = -sin(p * 2 * .pi) * 32
            for i in 0..<5 {
                let line = NSRect(x: r.minX + 18, y: r.maxY - 65 - Double(i) * 38 + offset, width: r.width - 54, height: 27)
                NSColor.white.setFill(); NSBezierPath(roundedRect: line, xRadius: 5, yRadius: 5).fill()
                label("Item 0\(i + 1)", at: NSPoint(x: line.minX + 9, y: line.midY - 4), size: 10, color: ink)
            }
            NSGraphicsContext.restoreGraphicsState()
            cursor = NSPoint(x: r.maxX - 27, y: r.midY)
            label("Scrolls here; pointer stays still", at: NSPoint(x: r.minX + 16, y: r.minY + 15), size: 11, color: ink)
        case .pause:
            let progress = min(1, max(0, (p - 0.27) * duration / 0.7))
            let paused = p >= 0.445
            label(paused ? "CONTROL PAUSED" : "Hold fist: 0.7 seconds", at: NSPoint(x: r.minX + 22, y: r.midY + 13), size: 14, color: ink)
            let bar = NSRect(x: r.minX + 22, y: r.midY - 13, width: r.width - 44, height: 6)
            ink.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
            mint.setFill(); NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: bar.width * progress, height: 6), xRadius: 3, yRadius: 3).fill()
            label("Release; repeat the fist to resume", at: NSPoint(x: r.minX + 16, y: r.minY + 15), size: 10, color: ink)
            return
        }
        drawCursor(at: cursor, pressed: contact > 0.85)
    }

    private var duration: Double { gesture.duration }
    private func ramp(_ value: Double, _ start: Double, _ end: Double) -> Double {
        let t = min(1, max(0, (value - start) / (end - start)))
        return t * t * (3 - 2 * t)
    }
    private func tube(_ points: [NSPoint], width: CGFloat, color: NSColor) {
        guard let first = points.first else { return }
        let path = NSBezierPath(); path.move(to: first)
        for point in points.dropFirst() { path.line(to: point) }
        path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.lineWidth = width + 3; ink.setStroke(); path.stroke()
        path.lineWidth = width; color.setStroke(); path.stroke()
    }
    private func drawCursor(at p: NSPoint, pressed: Bool) {
        if pressed {
            let ring = NSBezierPath(ovalIn: NSRect(x: p.x - 17, y: p.y - 17, width: 34, height: 34))
            ring.lineWidth = 3; gold.setStroke(); ring.stroke()
        }
        let cursor = NSBezierPath()
        cursor.move(to: p); cursor.line(to: NSPoint(x: p.x + 3, y: p.y - 25))
        cursor.line(to: NSPoint(x: p.x + 9, y: p.y - 19))
        cursor.line(to: NSPoint(x: p.x + 15, y: p.y - 30))
        cursor.line(to: NSPoint(x: p.x + 20, y: p.y - 27))
        cursor.line(to: NSPoint(x: p.x + 14, y: p.y - 16))
        cursor.line(to: NSPoint(x: p.x + 23, y: p.y - 15)); cursor.close()
        ink.setFill(); cursor.fill(); NSColor.white.setStroke(); cursor.lineWidth = 1.5; cursor.stroke()
    }
    private func arrow(from a: NSPoint, to b: NSPoint, color: NSColor) {
        let path = NSBezierPath(); path.move(to: a); path.line(to: b)
        let angle = atan2(b.y - a.y, b.x - a.x)
        path.move(to: NSPoint(x: b.x - cos(angle - 0.5) * 8, y: b.y - sin(angle - 0.5) * 8))
        path.line(to: b)
        path.line(to: NSPoint(x: b.x - cos(angle + 0.5) * 8, y: b.y - sin(angle + 0.5) * 8))
        path.lineWidth = 2; path.lineCapStyle = .round; color.withAlphaComponent(0.65).setStroke(); path.stroke()
    }
    private func label(_ text: String, at point: NSPoint, size: CGFloat, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
    }
}
