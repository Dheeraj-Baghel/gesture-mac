import AppKit
import GestureCore

// User request: show the gestures visually inside the app, not just in text.
// This tutorial uses original vector hand illustrations. It has no camera,
// ControlEngine or InputController reference and cannot post system input.
final class GestureDemoController: NSWindowController, NSWindowDelegate {
    private let demoView = GestureDemoView()
    private let selector = NSSegmentedControl(labels: ["Move", "Click", "Drag", "Scroll", "Right click", "Pause"], trackingMode: .selectOne, target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "")
    private let instructionLabel = NSTextField(wrappingLabelWithString: "")
    private let phaseLabel = NSTextField(labelWithString: "")
    private let playButton = NSButton(title: "Pause animation", target: nil, action: nil)
    private var timer: Timer?
    private var elapsed: Double = 0
    private var lastTick: Double = 0
    private var animationTicks = 0
    private var playing = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private(set) var selectedGesture: DemoGesture = .move
    var onClose: (() -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Gesture guide"
        window.minSize = NSSize(width: 760, height: 640)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        super.init(window: window)
        window.delegate = self
        buildInterface()
        playButton.title = playing ? "Pause animation" : "Play animation"
        select(.move)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func present(relativeTo parent: NSWindow?) {
        if let parent = parent, let window = window {
            window.setFrameOrigin(NSPoint(x: parent.frame.midX - window.frame.width / 2,
                                          y: parent.frame.midY - window.frame.height / 2))
        } else { window?.center() }
        window?.deminiaturize(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        startTimer()
    }

    func select(_ gesture: DemoGesture, phase: Double? = nil) {
        selectedGesture = gesture
        selector.selectedSegment = gesture.rawValue
        elapsed = (phase ?? (playing ? 0 : 0.52)) * gesture.duration
        titleLabel.stringValue = gesture.title
        instructionLabel.stringValue = gesture.instructions
        demoView.setAccessibilityLabel("\(gesture.title). \(gesture.instructions) Illustrated example only.")
        render()
    }

    private func buildInterface() {
        guard let window = window else { return }
        let root = DemoBackgroundView()
        window.contentView = root
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16)
        ])
        let eyebrow = NSTextField(labelWithString: "GESTURE GUIDE  /  WATCH, THEN TRY")
        eyebrow.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        eyebrow.textColor = .secondaryLabelColor
        stack.addArrangedSubview(eyebrow)
        titleLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        stack.addArrangedSubview(titleLabel)
        selector.target = self; selector.action = #selector(gestureChanged)
        selector.selectedSegment = 0
        selector.setAccessibilityLabel("Gesture to demonstrate")
        stack.addArrangedSubview(selector)
        instructionLabel.font = .systemFont(ofSize: 13)
        instructionLabel.textColor = .secondaryLabelColor
        instructionLabel.maximumNumberOfLines = 2
        instructionLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.addArrangedSubview(instructionLabel)
        instructionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        demoView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(demoView)
        NSLayoutConstraint.activate([
            demoView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            demoView.heightAnchor.constraint(equalToConstant: 310)
        ])
        phaseLabel.font = .systemFont(ofSize: 13, weight: .medium)
        stack.addArrangedSubview(phaseLabel)
        let controls = NSStackView(); controls.orientation = .horizontal; controls.spacing = 12
        playButton.target = self; playButton.action = #selector(togglePlay)
        controls.addArrangedSubview(playButton)
        controls.addArrangedSubview(NSButton(title: "Replay", target: self, action: #selector(replay)))
        controls.addArrangedSubview(NSButton(title: "Previous", target: self, action: #selector(previousGesture)))
        controls.addArrangedSubview(NSButton(title: "Next", target: self, action: #selector(nextGesture)))
        stack.addArrangedSubview(controls)
        let safety = NSTextField(wrappingLabelWithString: "ILLUSTRATION ONLY. No camera or permissions needed. Opening this guide disables real control; close it and enable control yourself when ready.")
        safety.font = .systemFont(ofSize: 11)
        safety.textColor = .secondaryLabelColor
        stack.addArrangedSubview(safety)
        safety.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    @objc private func gestureChanged() {
        guard let gesture = DemoGesture(rawValue: selector.selectedSegment) else { return }
        select(gesture)
    }
    @objc private func togglePlay() {
        playing.toggle()
        playButton.title = playing ? "Pause animation" : "Play animation"
        lastTick = ProcessInfo.processInfo.systemUptime
    }
    @objc private func replay() {
        elapsed = 0; playing = true; playButton.title = "Pause animation"; render()
    }
    @objc private func previousGesture() {
        select(DemoGesture(rawValue: (selectedGesture.rawValue + DemoGesture.allCases.count - 1) % DemoGesture.allCases.count)!)
    }
    @objc private func nextGesture() {
        select(DemoGesture(rawValue: (selectedGesture.rawValue + 1) % DemoGesture.allCases.count)!)
    }
    private func render() {
        let phase = (elapsed / selectedGesture.duration).truncatingRemainder(dividingBy: 1)
        demoView.gesture = selectedGesture
        demoView.phase = phase
        phaseLabel.stringValue = selectedGesture.caption(at: phase)
    }
    private func startTimer() {
        guard timer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationTicks += 1
            let now = ProcessInfo.processInfo.systemUptime
            let dt = min(0.1, max(0, now - self.lastTick))
            self.lastTick = now
            guard self.playing, self.window?.isVisible == true,
                  self.window?.isMiniaturized == false else { return }
            self.elapsed += dt
            self.render()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func windowWillClose(_ notification: Notification) { stopAnimation(); onClose?() }
    func stopAnimation() { timer?.invalidate(); timer = nil }
    var animationRunning: Bool { timer?.isValid == true }
    deinit { timer?.invalidate() }

    func smokeChecks() -> [String: Any] {
        var checks: [String: Bool] = [:]
        checks["animationTimerRunning"] = timer?.isValid == true
        checks["clockAdvancesOrReducedMotionRespected"] = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? !playing : elapsed > 0.01
        for gesture in DemoGesture.allCases {
            selector.selectedSegment = gesture.rawValue
            gestureChanged()
            checks["select-\(gesture.fileName)"] = selectedGesture == gesture && titleLabel.stringValue == gesture.title && instructionLabel.stringValue == gesture.instructions
        }
        select(.move); previousGesture()
        checks["previousWraps"] = selectedGesture == .pause
        nextGesture()
        checks["nextWraps"] = selectedGesture == .move
        replay()
        checks["replayResets"] = elapsed == 0 && playing
        togglePlay()
        checks["pauseWorks"] = !playing && playButton.title == "Play animation"
        let time = elapsed
        render()
        checks["pausedFrameStable"] = time == elapsed
        togglePlay()
        checks["resumeWorks"] = playing && playButton.title == "Pause animation"
        window?.layoutIfNeeded()
        if let root = window?.contentView {
            checks["canvasVisible"] = root.bounds.contains(demoView.convert(demoView.bounds, to: root))
            checks["playbackControlsVisible"] = root.bounds.contains(playButton.convert(playButton.bounds, to: root))
        }
        if let window = window, let root = window.contentView {
            let original = window.frame
            window.setFrame(NSRect(origin: original.origin, size: window.minSize), display: true)
            window.layoutIfNeeded()
            checks["minimumSizeCanvasVisible"] = root.bounds.contains(demoView.convert(demoView.bounds, to: root))
            checks["minimumSizeControlsVisible"] = root.bounds.contains(playButton.convert(playButton.bounds, to: root))
            window.setFrame(original, display: true)
        }
        return ["demoChecks": checks, "demoCheckCount": checks.count,
                "demoChecksPassed": checks.values.allSatisfy { $0 },
                "animationTimerTicks": animationTicks]
    }

    // Deterministic rendered samples for native smoke checks. No live gestures
    // or synthesized input are involved. Caller must already be in smoke mode.
    func captureSamples(into directory: URL) -> [String: Any] {
        stopAnimation()
        var count = 0
        let samplePhases: [Double] = [0.12, 0.52, 0.86]
        let original = selectedGesture
        for gesture in DemoGesture.allCases {
            for (index, phase) in samplePhases.enumerated() {
                select(gesture, phase: phase)
                window?.layoutIfNeeded()
                demoView.displayIfNeeded()
                guard let view = window?.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    let url = directory.appendingPathComponent("guide-\(gesture.fileName)-\(index + 1).png")
                    if (try? png.write(to: url)) != nil { count += 1 }
                }
            }
        }
        select(original)
        return ["demoGestureCount": DemoGesture.allCases.count, "demoSnapshots": count,
                "demoAnimationStoppedForCapture": timer == nil]
    }
}

private final class DemoBackgroundView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.956, green: 0.95, blue: 0.927, alpha: 1).setFill()
        dirtyRect.fill()
    }
}
