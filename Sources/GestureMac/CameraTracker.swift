import AppKit
import AVFoundation
import Vision
import ImageIO
import GestureCore

struct TrackingFrame {
    var hand: Hand?
    var issue: TrackingIssue
    var time: Double
    var latencyMS: Double
}

// Capture and Vision run serially away from the UI. Late camera frames are
// discarded rather than queued, so old gestures cannot drive present input.
final class CameraTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "local.gesturemac.camera", qos: .userInitiated)
    var onFrame: ((TrackingFrame) -> Void)?
    var onState: ((String, Bool) -> Void)?
    private let request = VNDetectHumanHandPoseRequest()
    private var videoInput: AVCaptureDeviceInput?
    private var configured = false
    private var lastProcessed: Double = 0
    private var accepting = false
    private let smokeTest: Bool
    private let generationLock = NSLock()
    private var generation = 0
    private var activeGeneration = 0

    init(smokeTest: Bool = false) {
        self.smokeTest = smokeTest
        super.init()
        // Two detections are needed to reject ambiguous multi-hand input.
        request.maximumHandCount = 2
        if #available(macOS 12.0, *) { request.revision = VNDetectHumanHandPoseRequestRevision1 }
    }

    static var authorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func devices() -> [AVCaptureDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video, position: .unspecified)
        return discovery.devices
    }

    func start(deviceID: String?) {
        guard !smokeTest else { publish("Camera disabled in smoke test", running: false); return }
        let token = advanceGeneration()
        switch Self.authorization {
        case .authorized: begin(deviceID: deviceID, token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self, self.isCurrent(token) else { return }
                if granted { self.begin(deviceID: deviceID, token: token) }
                else { self.publish("Camera denied. Allow Gesture Mac in Privacy & Security > Camera.", running: false, token: token) }
            }
        case .denied, .restricted:
            publish("Camera denied. Allow Gesture Mac in Privacy & Security > Camera.", running: false, token: token)
        @unknown default: publish("Camera access is unavailable.", running: false, token: token)
        }
    }

    func stop() {
        let token = advanceGeneration()
        queue.async { [weak self] in
            guard let self = self else { return }
            self.accepting = false
            if self.session.isRunning { self.session.stopRunning() }
            self.publish("Camera stopped - controls disabled", running: false, token: token)
        }
    }

    private func begin(deviceID: String?, token: Int) {
        queue.async { [weak self] in
            guard let self = self, self.isCurrent(token) else { return }
            do {
                if self.session.isRunning { self.session.stopRunning() }
                self.accepting = false
                let devices = Self.devices()
                guard let device = devices.first(where: { $0.uniqueID == deviceID }) ?? AVCaptureDevice.default(for: .video) ?? devices.first else {
                    self.publish("No camera found. Connect a webcam and refresh cameras.", running: false, token: token)
                    return
                }
                let input = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                if let old = self.videoInput { self.session.removeInput(old) }
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    self.publish("Cannot connect to this camera. Try another camera.", running: false, token: token)
                    return
                }
                self.session.addInput(input); self.videoInput = input
                if self.session.canSetSessionPreset(.vga640x480) { self.session.sessionPreset = .vga640x480 }
                if !self.configured {
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard self.session.canAddOutput(output) else {
                        self.session.commitConfiguration()
                        self.publish("Video capture is unavailable.", running: false, token: token)
                        return
                    }
                    self.session.addOutput(output)
                    if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    self.configured = true
                }
                self.session.commitConfiguration()
                do {
                    try device.lockForConfiguration()
                    let duration = CMTime(value: 1, timescale: 30)
                    if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                        device.activeVideoMinFrameDuration = duration
                        device.activeVideoMaxFrameDuration = duration
                    }
                    device.unlockForConfiguration()
                } catch { /* The device's default frame rate remains usable. */ }
                guard self.isCurrent(token) else { return }
                self.session.startRunning()
                guard self.isCurrent(token) else { self.session.stopRunning(); return }
                self.activeGeneration = token
                self.accepting = self.session.isRunning
                self.publish(self.session.isRunning ? "Camera on - preview only" : "Camera could not start. It may be in use.",
                             running: self.session.isRunning, token: token)
            } catch {
                self.publish("Camera error: \(error.localizedDescription)", running: false, token: token)
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let token = activeGeneration
        guard accepting, isCurrent(token), let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessed >= 1.0 / 30 else { return }
        lastProcessed = now
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up, options: [:])
            try handler.perform([request])
            let hands = request.results ?? []
            var detected: Hand?
            var issue: TrackingIssue = .missing
            if hands.count > 1 { issue = .multiple }
            else if let observation = hands.first {
                let recognized = try observation.recognizedPoints(.all)
                var points: [GestureCore.Joint: Landmark] = [:]
                for (key, value) in recognized {
                    if let joint = Self.jointMap[key] {
                        // Mirror once here, exactly as the preview layer does.
                        points[joint] = Landmark(Point(1 - value.location.x, value.location.y),
                                                 confidence: Double(value.confidence))
                    }
                }
                let hand = Hand(points: points, aspect: Double(CVPixelBufferGetWidth(pixel)) / Double(CVPixelBufferGetHeight(pixel)))
                if hand.isReliable() { detected = hand }
                else { issue = .unreliable }
            }
            let frame = TrackingFrame(hand: detected, issue: issue, time: now,
                                      latencyMS: (ProcessInfo.processInfo.systemUptime - now) * 1000)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isCurrent(token) else { return }
                self.onFrame?(frame)
            }
        } catch {
            let frame = TrackingFrame(hand: nil, issue: .stale, time: now, latencyMS: 0)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isCurrent(token) else { return }
                self.onFrame?(frame)
            }
        }
    }

    private func advanceGeneration() -> Int {
        generationLock.lock(); defer { generationLock.unlock() }
        generation += 1
        return generation
    }
    private func isCurrent(_ token: Int) -> Bool {
        generationLock.lock(); defer { generationLock.unlock() }
        return generation == token
    }
    private func publish(_ message: String, running: Bool, token: Int? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, token.map({ self.isCurrent($0) }) ?? true else { return }
            self.onState?(message, running)
        }
    }

    static let jointMap: [VNHumanHandPoseObservation.JointName: GestureCore.Joint] = [
        .wrist: .wrist,
        .thumbCMC: .thumbCMC, .thumbMP: .thumbMP, .thumbIP: .thumbIP, .thumbTip: .thumbTip,
        .indexMCP: .indexMCP, .indexPIP: .indexPIP, .indexDIP: .indexDIP, .indexTip: .indexTip,
        .middleMCP: .middleMCP, .middlePIP: .middlePIP, .middleDIP: .middleDIP, .middleTip: .middleTip,
        .ringMCP: .ringMCP, .ringPIP: .ringPIP, .ringDIP: .ringDIP, .ringTip: .ringTip,
        .littleMCP: .littleMCP, .littlePIP: .littlePIP, .littleDIP: .littleDIP, .littleTip: .littleTip
    ]
}
