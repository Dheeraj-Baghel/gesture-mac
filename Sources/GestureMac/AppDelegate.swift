import AppKit
import AVFoundation
import ApplicationServices
import GestureCore

// Safe-by-default native utility. No camera access until Start Camera, no input
// until Enable Control. Authorization is never modified programmatically.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let smokeTest = CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--demo-smoke-test")
    private lazy var camera = CameraTracker(smokeTest: smokeTest)
    private let preferences = Preferences()
    private lazy var engine = ControlEngine(settings: preferences.load())
    private let input = InputController()
    private let calibration = Calibration()
    private let hotKey = EmergencyHotKey()
    private var window: NSWindow!
    private var preview: PreviewView!
    private var statusItem: NSStatusItem!
    private var statusMenuItem = NSMenuItem(title: "Preview - controls disabled", action: nil, keyEquivalent: "")
    private var toggleMenuItem = NSMenuItem(title: "Enable Control...", action: #selector(toggleControl), keyEquivalent: "")
    private var cameraRunning = false
    private var startingCamera = false
    private var timer: Timer?
    private var gestureDemoController: GestureDemoController?
    private var observers: [NSObjectProtocol] = []
    private var lastFrameTime: Double = 0
    private var lastUIUpdate: Double = 0
    private var latestOutput = EngineOutput()
    private var displays: [CGDirectDisplayID] = []
    private var cameras: [AVCaptureDevice] = []
    private var cameraNameLabel: NSTextField!
    private var permissionLabel: NSTextField!
    private var stateLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var metricsLabel: NSTextField!
    private var calibrationLabel: NSTextField!
    private var cameraButton: NSButton!
    private var controlButton: NSButton!
    private var pauseButton: NSButton!
    private var calibrateButton: NSButton!
    private var permissionButton: NSButton!
    private var cameraPicker: NSPopUpButton!
    private var displayPicker: NSPopUpButton!
    private var smoothingSlider: NSSlider!
    private var naturalCheck: NSButton!
    private var rightCheck: NSButton!
    private var fistIndicator: NSProgressIndicator!
    private var hotKeyAvailable = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        input.dryRun = smokeTest
        NSApp.setActivationPolicy(.regular)
        buildMenus(); buildWindow(); buildStatusItem()
        refreshCameras(); refreshDisplays(); updatePermissions()
        hotKey.onStop = { [weak self] in self?.stopControl(reason: "Emergency stop - preview only") }
        hotKeyAvailable = hotKey.register()
        if !hotKeyAvailable { detailLabel.stringValue = "Global stop shortcut unavailable. Use the menu bar Stop or local Escape." }
        camera.onState = { [weak self] message, running in
            guard let self = self else { return }
            self.startingCamera = false; self.cameraRunning = running
            self.cameraButton.title = running ? "Stop camera" : "Start camera"
            self.cameraButton.isEnabled = true
            self.cameraPicker.isEnabled = !running
            self.cameraNameLabel.stringValue = message
            self.preview.displayStatus = message
            // The preview connection may not exist until capture starts.
            // Apply mirroring after it has been created, not just at init.
            if running { self.preview.needsLayout = true; self.preview.layoutSubtreeIfNeeded() }
            if !running { self.stopControl(reason: message); self.preview.hand = nil }
            self.updatePermissions()
        }
        camera.onFrame = { [weak self] frame in self?.receive(frame) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.watchdog() }
        RunLoop.main.add(timer!, forMode: .common)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.stopForSystem(reason: "Mac asleep or locked - restart camera to continue")
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: camera.session, queue: .main) { [weak self] note in
            self?.stopForSystem(reason: "Camera interrupted - restart camera to continue")
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: camera.session, queue: .main) { [weak self] _ in
            self?.stopForSystem(reason: "Camera interrupted - restart camera to continue")
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopControl(reason: "Displays changed - choose your display again")
            self?.refreshDisplays()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main) { [weak self] _ in self?.refreshCameras() })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main) { [weak self] _ in
            self?.stopForSystem(reason: "Camera disconnected - choose a camera")
            self?.refreshCameras()
        })
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--demo-smoke-test") { beginDemoSmokeTest() }
        else if smokeTest { beginSmokeTest() }
    }

    private func buildMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Gesture Mac", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Show Gesture Mac", action: #selector(showWindow), keyEquivalent: "0")
        appMenu.addItem(withTitle: "Gesture demo", action: #selector(showGestureDemo), keyEquivalent: "d")
        appMenu.addItem(withTitle: "Stop Control", action: #selector(emergencyStop), keyEquivalent: ".")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Gesture Mac", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Gesture Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let windowItem = NSMenuItem(); let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu; main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
        for item in appMenu.items where item.action == #selector(showAbout) || item.action == #selector(showWindow) || item.action == #selector(emergencyStop) || item.action == #selector(showGestureDemo) { item.target = self }
    }

    private func buildWindow() {
        window = GestureWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 805),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        (window as? GestureWindow)?.onEscape = { [weak self] in
            self?.stopControl(reason: "Escape pressed - preview only")
        }
        window.delegate = self; window.title = "Gesture Mac"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed: 0.956, green: 0.95, blue: 0.927, alpha: 1)
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 990, height: 790)
        window.isReleasedWhenClosed = false
        window.center()
        let root = GestureBackgroundView(); root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root
        let outer = NSStackView(); outer.orientation = .vertical; outer.alignment = .leading; outer.spacing = 12
        outer.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            outer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            outer.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            outer.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20)
        ])
        let brand = text("GESTURE MAC  /  LOCAL-FIRST", size: 11, weight: .bold, color: .secondaryLabelColor)
        outer.addArrangedSubview(brand)
        let header = NSStackView(); header.orientation = .horizontal; header.spacing = 16
        let title = text("Your hand. Your cursor.", size: 32, weight: .semibold)
        header.addArrangedSubview(title)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(spacer)
        let badge = text("APPLE VISION  ·  NO CLOUD", size: 11, weight: .medium, color: .secondaryLabelColor)
        header.addArrangedSubview(badge)
        let demoButton = button("Watch gesture demo", action: #selector(showGestureDemo))
        demoButton.toolTip = "Animated hand guide. No camera needed; real control stays disabled."
        header.addArrangedSubview(demoButton)
        outer.addArrangedSubview(header); header.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        outer.addArrangedSubview(text("Move, click and scroll with one hand. Start with a safe preview, then take control.", size: 14, color: .secondaryLabelColor))

        let middle = NSStackView(); middle.orientation = .horizontal; middle.alignment = .top; middle.spacing = 24
        preview = PreviewView(session: camera.session)
        preview.area = engine.settings.area
        preview.translatesAutoresizingMaskIntoConstraints = false
        middle.addArrangedSubview(preview)
        let controls = NSStackView(); controls.orientation = .vertical; controls.alignment = .leading; controls.spacing = 8
        middle.addArrangedSubview(controls)
        controls.widthAnchor.constraint(equalToConstant: 306).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 412).isActive = true
        outer.addArrangedSubview(middle); middle.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true

        stateLabel = text("PREVIEW ONLY", size: 11, weight: .bold, color: .secondaryLabelColor)
        controls.addArrangedSubview(stateLabel)
        permissionLabel = wrapping("Camera off. Accessibility permission not checked.", size: 12)
        controls.addArrangedSubview(permissionLabel)
        let permissionRow = NSStackView(); permissionRow.orientation = .horizontal; permissionRow.spacing = 8
        permissionButton = button("Allow control access", action: #selector(requestAccessibility))
        permissionButton.toolTip = "Open macOS Accessibility settings; authorization remains your choice."
        permissionRow.addArrangedSubview(permissionButton)
        permissionRow.addArrangedSubview(button("Camera settings", action: #selector(openCameraSettings)))
        controls.addArrangedSubview(permissionRow)

        let cameraRow = NSStackView(); cameraRow.orientation = .horizontal; cameraRow.spacing = 6
        cameraPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        cameraPicker.target = self; cameraPicker.action = #selector(cameraChanged)
        cameraPicker.setAccessibilityLabel("Camera")
        cameraRow.addArrangedSubview(cameraPicker)
        cameraRow.addArrangedSubview(button("Refresh", action: #selector(refreshCameraAction)))
        controls.addArrangedSubview(cameraRow)
        cameraRow.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        cameraPicker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cameraButton = button("Start camera", action: #selector(toggleCamera)); controls.addArrangedSubview(cameraButton)
        controls.addArrangedSubview(text("CONTROL THIS DISPLAY", size: 10, weight: .bold, color: .secondaryLabelColor))
        displayPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        displayPicker.target = self; displayPicker.action = #selector(displayChanged)
        displayPicker.setAccessibilityLabel("Display to control")
        controls.addArrangedSubview(displayPicker)
        displayPicker.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        let actionRow = NSStackView(); actionRow.orientation = .horizontal; actionRow.spacing = 8
        controlButton = button("Enable control", action: #selector(toggleControl)); controlButton.bezelColor = .controlAccentColor
        controlButton.isEnabled = false; actionRow.addArrangedSubview(controlButton)
        pauseButton = button("Pause", action: #selector(togglePause)); pauseButton.isEnabled = false
        actionRow.addArrangedSubview(pauseButton); controls.addArrangedSubview(actionRow)
        calibrateButton = button("Calibrate movement range", action: #selector(toggleCalibration)); calibrateButton.isEnabled = false
        controls.addArrangedSubview(calibrateButton)
        calibrationLabel = wrapping("Optional: set a comfortable range. Controls stay off during calibration.", size: 11)
        controls.addArrangedSubview(calibrationLabel)
        fistIndicator = NSProgressIndicator(); fistIndicator.style = .bar; fistIndicator.isIndeterminate = false
        fistIndicator.minValue = 0; fistIndicator.maxValue = 1; fistIndicator.doubleValue = 0
        controls.addArrangedSubview(fistIndicator)
        fistIndicator.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        let stop = button("STOP  ·  Control + Option + Command + G", action: #selector(emergencyStop))
        stop.contentTintColor = .systemRed; stop.toolTip = "Global emergency stop. Escape also stops while this window is focused."
        controls.addArrangedSubview(stop)
        for view in [permissionLabel!, calibrationLabel!] { view.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true }

        let feedback = NSStackView(); feedback.orientation = .horizontal; feedback.spacing = 14
        detailLabel = text("Start the camera to see your hand landmarks.", size: 13, weight: .medium)
        feedback.addArrangedSubview(detailLabel)
        let feedbackSpacer = NSView(); feedbackSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        feedback.addArrangedSubview(feedbackSpacer)
        metricsLabel = text("CAMERA OFF", size: 10, weight: .medium, color: .secondaryLabelColor)
        feedback.addArrangedSubview(metricsLabel)
        outer.addArrangedSubview(feedback); feedback.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        cameraNameLabel = text("No camera is running. Nothing is recorded or uploaded.", size: 11, color: .secondaryLabelColor)
        outer.addArrangedSubview(cameraNameLabel)

        let rule = NSBox(); rule.boxType = .separator; outer.addArrangedSubview(rule)
        rule.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        let gestureRow = NSStackView(); gestureRow.orientation = .horizontal; gestureRow.spacing = 16; gestureRow.distribution = .fillEqually
        let guide: [(String, String)] = [
            ("01  POINT", "Index up, other fingers curled. Move your hand."),
            ("02  PINCH", "Thumb + index: click. Hold to drag; open to drop."),
            ("03  TWO FINGERS", "Index + middle up. Move hand up/down to scroll."),
            ("04  FIST", "Hold 0.7 sec to pause. Release, repeat to resume.")
        ]
        for (heading, body) in guide {
            let card = NSStackView(); card.orientation = .vertical; card.alignment = .leading; card.spacing = 6
            card.addArrangedSubview(text(heading, size: 11, weight: .bold))
            let description = wrapping(body, size: 12); card.addArrangedSubview(description)
            description.widthAnchor.constraint(equalTo: card.widthAnchor).isActive = true
            gestureRow.addArrangedSubview(card)
        }
        outer.addArrangedSubview(gestureRow); gestureRow.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        let options = NSStackView(); options.orientation = .horizontal; options.spacing = 16
        rightCheck = NSButton(checkboxWithTitle: "Right click (thumb + middle; index up)", target: self, action: #selector(settingsChanged))
        rightCheck.state = engine.settings.rightClickEnabled ? .on : .off
        naturalCheck = NSButton(checkboxWithTitle: "Natural scroll", target: self, action: #selector(settingsChanged))
        naturalCheck.state = engine.settings.naturalScrolling ? .on : .off
        options.addArrangedSubview(rightCheck); options.addArrangedSubview(naturalCheck)
        options.addArrangedSubview(text("Smoothing", size: 11))
        smoothingSlider = NSSlider(value: engine.settings.smoothingSeconds, minValue: 0.02, maxValue: 0.18, target: self, action: #selector(settingsChanged))
        smoothingSlider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        smoothingSlider.setAccessibilityLabel("Pointer smoothing; higher is steadier but slower")
        options.addArrangedSubview(smoothingSlider)
        options.addArrangedSubview(button("Reset range", action: #selector(resetRange)))
        outer.addArrangedSubview(options)
        outer.addArrangedSubview(text("One hand · good light · rest often. Open palm rests the pointer. No keyboard typing or system security bypass.", size: 11, color: .secondaryLabelColor))
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "Gesture Mac")
        statusItem.button?.toolTip = "Gesture Mac - controls disabled"
        let menu = NSMenu()
        menu.addItem(statusMenuItem); menu.addItem(.separator())
        menu.addItem(withTitle: "Show Gesture Mac", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Gesture demo", action: #selector(showGestureDemo), keyEquivalent: "")
        menu.addItem(toggleMenuItem)
        menu.addItem(withTitle: "Pause / Resume", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(withTitle: "STOP Control", action: #selector(emergencyStop), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Gesture Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
    }

    private func receive(_ frame: TrackingFrame) {
        guard cameraRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - frame.time < 0.2 else {
            apply(engine.process(hand: nil, now: now, issue: .stale)); preview.hand = nil; return
        }
        lastFrameTime = now
        preview.hand = frame.hand
        if calibration.inProgress {
            calibration.process(hand: frame.hand, now: frame.time)
            calibrationLabel.stringValue = calibration.message
            fistIndicator.doubleValue = calibration.progress
            preview.calibrationStage = calibration.stage
            preview.displayStatus = calibration.message
            if let area = calibration.result {
                engine.settings.area = area; preferences.save(engine.settings); preview.area = area
                calibrateButton.title = "Calibrate movement range"
                updatePermissions()
            }
        } else { apply(engine.process(hand: frame.hand, now: frame.time, issue: frame.issue)) }
        if now - lastUIUpdate > 0.15 {
            metricsLabel.stringValue = "\(Int(frame.latencyMS)) ms VISION · \(frame.hand == nil ? "NO HAND" : "1 HAND")"
            lastUIUpdate = now
        }
    }

    private func apply(_ output: EngineOutput) {
        input.apply(output.actions)
        latestOutput = output
        detailLabel?.stringValue = output.message
        stateLabel?.stringValue = !output.enabled ? "PREVIEW ONLY" : output.paused ? "PAUSED" : "CONTROL ENABLED"
        stateLabel?.textColor = output.enabled && !output.paused ? .systemGreen : .secondaryLabelColor
        controlButton?.title = output.enabled ? "Disable control" : "Enable control"
        pauseButton?.title = output.paused ? "Resume" : "Pause"
        pauseButton?.isEnabled = output.enabled
        preview?.controlsActive = output.enabled && !output.paused
        preview?.displayStatus = output.message
        fistIndicator?.doubleValue = output.fistProgress
        statusMenuItem.title = !output.enabled ? "Preview - controls disabled" : output.paused ? "Paused" : "Control enabled"
        toggleMenuItem.title = output.enabled ? "Disable Control" : "Enable Control..."
        statusItem?.button?.toolTip = "Gesture Mac - \(statusMenuItem.title)"
        statusItem?.button?.image = NSImage(systemSymbolName: output.enabled && !output.paused ? "hand.point.up.left.fill" : "hand.point.up.left", accessibilityDescription: "Gesture Mac")
    }

    private func watchdog() {
        guard !smokeTest else { return }
        if engine.enabled && !InputController.trusted { stopControl(reason: "Accessibility access removed - controls disabled") }
        if cameraRunning && CameraTracker.authorization != .authorized {
            stopForSystem(reason: "Camera permission removed - controls disabled")
        }
        if engine.enabled {
            let result = engine.tick(now: ProcessInfo.processInfo.systemUptime)
            if result.paused != latestOutput.paused || !result.actions.isEmpty { apply(result) }
        }
        if cameraRunning && lastFrameTime > 0 && ProcessInfo.processInfo.systemUptime - lastFrameTime > 0.35 {
            preview.hand = nil
            if calibration.inProgress {
                calibration.process(hand: nil, now: ProcessInfo.processInfo.systemUptime)
                calibrationLabel.stringValue = "Tracking interrupted - hold your pose again."
            }
        }
        updatePermissions()
    }

    private func updatePermissions() {
        guard permissionLabel != nil else { return }
        let cameraText: String
        switch CameraTracker.authorization {
        case .authorized: cameraText = cameraRunning ? "Camera: on" : "Camera: allowed"
        case .notDetermined: cameraText = "Camera: not requested"
        default: cameraText = "Camera: not allowed"
        }
        let trusted = InputController.trusted
        permissionLabel.stringValue = "\(cameraText)\nAccessibility: \(trusted ? "allowed" : "needed for control")"
        permissionButton.title = trusted ? "Accessibility settings" : "Allow control access"
        // Leave enable clickable when camera runs so the permission guidance is
        // discoverable; the action itself refuses input until trusted.
        controlButton.isEnabled = cameraRunning && !calibration.inProgress && !displays.isEmpty && !isGestureDemoVisible
        calibrateButton.isEnabled = cameraRunning && !isGestureDemoVisible
    }

    @objc private func toggleCamera() {
        if cameraRunning || startingCamera {
            stopControl(reason: "Camera stopped - controls disabled")
            calibration.cancel(); calibrateButton.title = "Calibrate movement range"
            preview.calibrationStage = .idle
            camera.stop()
        } else {
            startingCamera = true; cameraButton.isEnabled = false
            cameraNameLabel.stringValue = "Starting camera..."
            let id = cameras.indices.contains(cameraPicker.indexOfSelectedItem) ? cameras[cameraPicker.indexOfSelectedItem].uniqueID : nil
            camera.start(deviceID: id)
        }
    }
    @objc private func toggleControl() {
        if engine.enabled { stopControl(reason: "Control disabled - preview only"); return }
        guard !isGestureDemoVisible else {
            detailLabel.stringValue = "Close the gesture demo before enabling real control."
            gestureDemoController?.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard cameraRunning, !calibration.inProgress else { showWindow(); return }
        guard !displays.isEmpty else { detailLabel.stringValue = "No display available - reconnect or wake your display."; return }
        guard InputController.trusted else { requestAccessibility(); detailLabel.stringValue = "Allow Gesture Mac in Accessibility, then click Enable control again."; return }
        apply(engine.enable(now: ProcessInfo.processInfo.systemUptime))
    }
    @objc private func togglePause() {
        guard engine.enabled else { return }
        if engine.paused { apply(engine.resume(now: ProcessInfo.processInfo.systemUptime)) }
        else { apply(engine.pause(reason: "Paused - hold a fist or click Resume")) }
    }
    @objc private func emergencyStop() { stopControl(reason: "Stopped - controls disabled") }
    private func stopControl(reason: String) {
        apply(engine.disable(reason: reason)); input.releaseAll()
    }
    private func stopForSystem(reason: String) {
        stopControl(reason: reason)
        calibration.cancel(); preview.calibrationStage = .idle
        calibrateButton.title = "Calibrate movement range"
        cameraRunning = false; startingCamera = false; camera.stop()
        cameraButton.title = "Start camera"; cameraButton.isEnabled = true
        cameraPicker.isEnabled = true
        preview.hand = nil; cameraNameLabel.stringValue = reason
        updatePermissions()
    }
    @objc private func toggleCalibration() {
        guard !isGestureDemoVisible else { return }
        if calibration.inProgress {
            calibration.cancel(); preview.calibrationStage = .idle
            calibrateButton.title = "Calibrate movement range"
        } else {
            stopControl(reason: "Calibrating - input disabled")
            calibration.start(); preview.calibrationStage = calibration.stage
            calibrateButton.title = "Cancel calibration"
        }
        calibrationLabel.stringValue = calibration.message
        updatePermissions()
    }
    @objc private func resetRange() {
        stopControl(reason: "Range reset - preview only")
        calibration.cancel(); preview.calibrationStage = .idle
        engine.settings.area = MappingArea(); preview.area = engine.settings.area
        preferences.save(engine.settings)
        calibrateButton.title = "Calibrate movement range"
        calibrationLabel.stringValue = "Default movement range restored."
        updatePermissions()
    }
    @objc private func settingsChanged() {
        apply(engine.pause(reason: "Settings changed - resume when ready"))
        engine.settings.smoothingSeconds = smoothingSlider.doubleValue
        engine.settings.naturalScrolling = naturalCheck.state == .on
        engine.settings.rightClickEnabled = rightCheck.state == .on
        engine.settings.sanitize(); preferences.save(engine.settings)
    }
    @objc private func requestAccessibility() {
        if smokeTest { return }
        stopControl(reason: "Grant Accessibility, then enable control yourself")
        if !InputController.trusted { InputController.requestPermission() }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    @objc private func openCameraSettings() {
        if smokeTest { return }
        stopControl(reason: "Camera settings - controls disabled")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
    }
    @objc private func refreshCameraAction() { refreshCameras() }
    private func refreshCameras() {
        guard cameraPicker != nil else { return }
        cameras = CameraTracker.devices()
        cameraPicker.removeAllItems()
        cameraPicker.addItems(withTitles: cameras.map(\.localizedName))
        if cameras.isEmpty { cameraPicker.addItem(withTitle: "No camera found") }
        if let id = preferences.cameraID, let index = cameras.firstIndex(where: { $0.uniqueID == id }) { cameraPicker.selectItem(at: index) }
    }
    @objc private func cameraChanged() {
        stopControl(reason: "Camera changed - preview only")
        if cameras.indices.contains(cameraPicker.indexOfSelectedItem) { preferences.cameraID = cameras[cameraPicker.indexOfSelectedItem].uniqueID }
    }
    private func refreshDisplays() {
        var count: UInt32 = 0
        // An asleep display is online but can disappear from the active list.
        // Enumerate it for setup without waking it or sending it any input.
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        if count > 0 { CGGetOnlineDisplayList(count, &ids, &count) }
        displays = Array(ids.prefix(Int(count))).filter { CGDisplayBounds($0).width > 1 }
        displayPicker.removeAllItems()
        let screens = NSScreen.screens
        for (index, id) in displays.enumerated() {
            let screen = screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
            let name = screen?.localizedName ?? "Display \(index + 1)"
            displayPicker.addItem(withTitle: "\(name)\(id == CGMainDisplayID() ? " (main)" : "")")
        }
        let selected = preferences.displayID.flatMap { displays.firstIndex(of: $0) } ?? displays.firstIndex(of: CGMainDisplayID()) ?? 0
        if !displays.isEmpty { displayPicker.selectItem(at: selected); input.displayID = displays[selected] }
    }
    @objc private func displayChanged() {
        stopControl(reason: "Display changed - enable when ready")
        guard displays.indices.contains(displayPicker.indexOfSelectedItem) else { return }
        input.displayID = displays[displayPicker.indexOfSelectedItem]
        preferences.displayID = input.displayID
    }
    private var isGestureDemoVisible: Bool { gestureDemoController?.window?.isVisible == true }
    @objc private func showGestureDemo() {
        // Teaching must never leave system input enabled or silently resume it.
        stopControl(reason: "Watching gesture demo - real control disabled")
        calibration.cancel(); preview.calibrationStage = .idle
        calibrateButton.title = "Calibrate movement range"
        if gestureDemoController == nil {
            let guide = GestureDemoController()
            guide.onClose = { [weak self] in
                guard let self = self else { return }
                self.stopControl(reason: "Demo closed - real control remains disabled")
                DispatchQueue.main.async { [weak self] in self?.updatePermissions() }
            }
            gestureDemoController = guide
        }
        gestureDemoController?.present(relativeTo: window)
        updatePermissions()
    }
    @objc private func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Gesture Mac", .applicationVersion: "0.1.0",
            .credits: NSAttributedString(string: "Local Apple Vision hand tracking. No accounts, recordings or uploads.\nPrototype: physical hand accuracy and system-wide control need your permission and testing.")])
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stopControl(reason: "Window closed - controls disabled")
        cameraRunning = false; camera.stop(); window.orderOut(nil)
        return false
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); gestureDemoController?.stopAnimation()
        stopControl(reason: "Quitting"); camera.stop()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = NSFont.systemFont(ofSize: size, weight: weight); label.textColor = color
        label.isSelectable = false
        return label
    }
    private func wrapping(_ string: String, size: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = NSFont.systemFont(ofSize: size); label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 3
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }
    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded; button.controlSize = .regular
        return button
    }

    private func beginDemoSmokeTest() {
        let path = ProcessInfo.processInfo.environment["GESTURE_MAC_DEMO_REPORT"]
        // Simulated activation is still hard-blocked by InputController.dryRun.
        apply(engine.enable(now: ProcessInfo.processInfo.systemUptime))
        showGestureDemo()
        let openingDisabledControl = !engine.enabled
        toggleControl()
        let reenableBlocked = !engine.enabled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, let demo = self.gestureDemoController else { return }
            var report: [String: Any] = [
                "demoOpens": self.isGestureDemoVisible,
                "openingDisabledControl": openingDisabledControl,
                "reenableBlockedWhileDemoOpen": reenableBlocked,
                "cameraRunning": self.camera.session.isRunning,
                "postedEvents": self.input.postedEvents,
                "inputHardDisabled": self.input.dryRun
            ]
            report.merge(demo.smokeChecks()) { _, new in new }
            if let path = path {
                let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
                report.merge(demo.captureSamples(into: directory)) { _, new in new }
                demo.present(relativeTo: self.window)
                report["demoAnimationRestartsOnReopen"] = demo.animationRunning
                demo.window?.performClose(nil)
                report["demoAnimationStopsOnClose"] = !demo.animationRunning
                report["closingLeavesControlDisabled"] = !self.engine.enabled
                report["demoWindowCloses"] = !self.isGestureDemoVisible
                self.window.layoutIfNeeded()
                if let view = self.window.contentView,
                   let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try? png.write(to: directory.appendingPathComponent("main-with-demo.png"))
                    }
                }
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            }
            print("Gesture demo smoke test: \(report)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
        }
    }

    // A bounded native UI smoke run never requests camera/Accessibility, posts
    // input, or pretends synthetic landmarks prove real-hand accuracy.
    private func beginSmokeTest() {
        preview.showDemo = true
        detailLabel.stringValue = "Smoke test: input is hard-disabled; camera is off."
        let path = ProcessInfo.processInfo.environment["GESTURE_MAC_SMOKE_REPORT"]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self else { return }
            self.window.layoutIfNeeded()
            let screens = self.displays.count
            let rect = self.preview.convert(self.preview.bounds, to: self.window.contentView)
            let initialSafe = !self.engine.enabled && !self.camera.session.isRunning && !self.controlButton.isEnabled
            self.input.apply([.move(Point(0.5, 0.5)), .leftDown(Point(0.5, 0.5)), .leftUp(Point(0.5, 0.5)), .rightClick(Point(0.5, 0.5)), .scroll(20)])
            self.apply(self.engine.enable(now: ProcessInfo.processInfo.systemUptime))
            self.emergencyStop()
            let emergencyStopped = !self.engine.enabled && !self.input.leftHeld
            self.detailLabel.stringValue = "Smoke test: input is hard-disabled; camera is off."
            var report: [String: Any] = [
                "launched": true,
                "initialSafeState": initialSafe,
                "emergencyStopDisabledControl": emergencyStopped,
                "dryRunRejectedAllInput": self.input.postedEvents == 0 && !self.input.leftHeld,
                "cameraRunning": self.camera.session.isRunning,
                "inputDryRun": self.input.dryRun,
                "postedEvents": self.input.postedEvents,
                "controlEnabled": self.engine.enabled,
                "previewWidth": rect.width,
                "previewHeight": rect.height,
                "displayCount": screens,
                "cameraCount": self.cameras.count,
                "hotKeyRegistered": self.hotKeyAvailable,
                "windowWidth": self.window.frame.width,
                "windowHeight": self.window.frame.height,
                "settingsVisible": self.window.contentView?.bounds.contains(self.rightCheck.convert(self.rightCheck.bounds, to: self.window.contentView)) ?? false,
                "controlsVisible": self.window.contentView?.bounds.contains(self.controlButton.convert(self.controlButton.bounds, to: self.window.contentView)) ?? false
            ]
            report.merge(NativeChecks.run(input: self.input)) { _, new in new }
            if let path = path, let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
            print("Gesture Mac smoke test: \(report)")
            if CommandLine.arguments.contains("--snapshot"), let view = self.window.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let path = path, let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("app-preview.png"))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
    }
}

private final class GestureWindow: NSWindow {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

private final class GestureBackgroundView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.956, green: 0.95, blue: 0.927, alpha: 1).setFill()
        dirtyRect.fill()
    }
}
