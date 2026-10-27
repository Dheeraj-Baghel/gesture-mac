import AppKit
import AVFoundation
import GestureCore

final class PreviewView: NSView {
    private let videoLayer = AVCaptureVideoPreviewLayer()
    var hand: Hand? { didSet { needsDisplay = true } }
    var area = MappingArea() { didSet { needsDisplay = true } }
    var calibrationStage: Calibration.Stage = .idle { didSet { needsDisplay = true } }
    var displayStatus = "Camera is off" { didSet { needsDisplay = true } }
    var showDemo = false { didSet { needsDisplay = true } }
    var controlsActive = false { didSet { needsDisplay = true } }
    private var aspect = 4.0 / 3.0

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
        layer?.cornerRadius = 16; layer?.masksToBounds = true
        videoLayer.session = session
        videoLayer.videoGravity = .resizeAspect
        // Video is a sublayer; a separate drawing view above it carries guides.
        layer?.addSublayer(videoLayer)
        addSubview(overlay)
        setAccessibilityLabel("Mirrored camera preview with hand skeleton and calibrated pointer range")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
    private lazy var overlay: PreviewOverlay = {
        let view = PreviewOverlay()
        view.owner = self
        return view
    }()
    override func layout() {
        super.layout()
        videoLayer.frame = bounds
        overlay.frame = bounds
        if let connection = videoLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        overlay.needsDisplay = true
    }
    override var needsDisplay: Bool {
        didSet { if needsDisplay { overlay.needsDisplay = true } }
    }
    fileprivate func drawOverlay() {
        if let hand = hand { aspect = hand.aspect }
        let size: NSSize
        if bounds.width / max(1, bounds.height) > aspect {
            size = NSSize(width: bounds.height * aspect, height: bounds.height)
        } else { size = NSSize(width: bounds.width, height: bounds.width / aspect) }
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                          width: size.width, height: size.height)
        func position(_ p: Point) -> NSPoint {
            NSPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
        }
        if showDemo && hand == nil {
            NSColor(calibratedWhite: 0.1, alpha: 1).setFill(); bounds.fill()
        }
        let range = NSRect(x: rect.minX + area.left * rect.width,
                           y: rect.minY + area.bottom * rect.height,
                           width: (area.right - area.left) * rect.width,
                           height: (area.top - area.bottom) * rect.height)
        let guide = NSBezierPath(roundedRect: range, xRadius: 12, yRadius: 12)
        guide.setLineDash([6, 6], count: 2, phase: 0)
        guide.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.45).setStroke(); guide.stroke()
        drawText("COMFORTABLE MOVEMENT RANGE", at: NSPoint(x: range.minX + 12, y: range.maxY - 24),
                 color: .white.withAlphaComponent(0.7), size: 10, weight: .medium)
        if let hand = hand {
            let fingers: [[Joint]] = [
                [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
                [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
                [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
                [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
                [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]
            ]
            let mint = NSColor(calibratedRed: 0.55, green: 0.92, blue: 0.72, alpha: 1)
            for finger in fingers {
                let line = NSBezierPath(); var begun = false
                for joint in finger {
                    guard let lm = hand.points[joint], lm.confidence >= 0.4 else { continue }
                    if !begun { line.move(to: position(lm.point)); begun = true }
                    else { line.line(to: position(lm.point)) }
                }
                line.lineWidth = 3; line.lineCapStyle = .round
                mint.withAlphaComponent(0.85).setStroke(); line.stroke()
            }
            for lm in hand.points.values where lm.confidence >= 0.4 {
                let p = position(lm.point)
                let circle = NSBezierPath(ovalIn: NSRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
                mint.setFill(); circle.fill()
            }
            let p = position(hand.palmCenter)
            let anchor = NSBezierPath(ovalIn: NSRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
            anchor.lineWidth = 2; NSColor.white.setStroke(); anchor.stroke()
        }
        if calibrationStage == .upperLeft || calibrationStage == .lowerRight {
            let point = calibrationStage == .upperLeft ? Point(area.left, area.top) : Point(area.right, area.bottom)
            let p = position(point)
            NSColor.systemOrange.setStroke()
            let circle = NSBezierPath(ovalIn: NSRect(x: p.x - 20, y: p.y - 20, width: 40, height: 40))
            circle.lineWidth = 4; circle.stroke()
        }
        let statusBackground = NSBezierPath(roundedRect: NSRect(x: 16, y: 14, width: max(80, bounds.width - 32), height: 40), xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.65).setFill(); statusBackground.fill()
        drawText(displayStatus, at: NSPoint(x: 28, y: 27), color: .white, size: 12, weight: .medium)
        drawText(showDemo ? "DEMO - NO CAMERA OR INPUT" : (controlsActive ? "CONTROL ACTIVE" : "SAFE PREVIEW"),
                 at: NSPoint(x: 18, y: bounds.height - 30),
                 color: controlsActive ? .systemOrange : .white, size: 11, weight: .bold)
    }
    private func drawText(_ text: String, at point: NSPoint, color: NSColor,
                          size: CGFloat, weight: NSFont.Weight) {
        (text as NSString).draw(at: point, withAttributes: [
            .foregroundColor: color, .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        ])
    }
}
private final class PreviewOverlay: NSView {
    weak var owner: PreviewView?
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { owner?.drawOverlay() }
}
