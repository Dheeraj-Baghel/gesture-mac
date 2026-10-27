import AppKit
import Vision
import CoreVideo
import GestureCore

// Runs only with --smoke-test. A generated blank pixel buffer validates that
// Vision's native request executes; this is NOT a physical-hand accuracy test.
enum NativeChecks {
    static func run(input: InputController) -> [String: Any] {
        let bounds = CGDisplayBounds(input.displayID)
        let origin = input.screenPoint(Point(0, 0))
        let corner = input.screenPoint(Point(1, 1))
        var report: [String: Any] = [
            "jointMapCount": CameraTracker.jointMap.count,
            "displayMappingCorrect": bounds.width > 1 && bounds.height > 1 &&
                origin == bounds.origin && abs(corner.x - (bounds.maxX - 1)) < 0.001 &&
                abs(corner.y - (bounds.maxY - 1)) < 0.001
        ]
        var pixel: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 640, 480,
                                         kCVPixelFormatType_32BGRA, nil, &pixel)
        guard status == kCVReturnSuccess, let pixel = pixel else {
            report["visionBlankFrameSucceeded"] = false
            report["visionError"] = "Could not allocate test frame: \(status)"
            return report
        }
        CVPixelBufferLockBaseAddress(pixel, [])
        if let base = CVPixelBufferGetBaseAddress(pixel) {
            memset(base, 0, CVPixelBufferGetDataSize(pixel))
        }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        do {
            let request = VNDetectHumanHandPoseRequest()
            request.maximumHandCount = 2
            request.revision = VNDetectHumanHandPoseRequestRevision1
            let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up, options: [:])
            let start = ProcessInfo.processInfo.systemUptime
            try handler.perform([request])
            report["visionBlankFrameSucceeded"] = true
            report["visionBlankFrameHandCount"] = request.results?.count ?? 0
            report["visionBlankFrameMS"] = (ProcessInfo.processInfo.systemUptime - start) * 1000
        } catch {
            report["visionBlankFrameSucceeded"] = false
            report["visionError"] = error.localizedDescription
        }
        return report
    }
}
