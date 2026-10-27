import Foundation
import Darwin

// Tiny, explicit runner for CLT-only machines. Assertions record real failures
// and the process exits nonzero. No XCTest shims, mocks of the OS, or packages.
private var assertions = 0
private var failures = 0
private var results: [[String: Any]] = []
func expect(_ condition: @autoclosure () -> Bool, _ note: String = "Expected true",
            file: StaticString = #fileID, line: UInt = #line) {
    assertions += 1
    if !condition() { failures += 1; print("  FAIL \(file):\(line): \(note)") }
}
func equal<T: Equatable>(_ actual: T, _ expected: T,
                          file: StaticString = #fileID, line: UInt = #line) {
    expect(actual == expected, "\(actual) != \(expected)", file: file, line: line)
}
func run(_ name: String, _ body: () -> Void) {
    let before = failures
    body()
    let pass = failures == before
    print("\(pass ? "PASS" : "FAIL") \(name)")
    results.append(["name": name, "passed": pass])
}
let e = ControlEngineTests()
run("Synthetic poses", e.testSyntheticPosesClassify)
run("Preview never controls", e.testPreviewNeverProducesInput)
run("No startup pinch click", e.testPinchedStartupCannotClick)
run("Neutral hold before pointer", e.testPointRequiresNeutralHold)
run("One down and up per click", e.testClickHasOneDownOneUp)
run("Short pinch debounce", e.testShortPinchDoesNotClick)
run("Tap cursor freeze", e.testTapPinchFreezesPointer)
run("Drag and release", e.testLongPinchDragsAndReleases)
run("Immediate hand-loss release", e.testNoHandImmediatelyReleasesAndRequiresNewPoint)
run("Low confidence release", e.testInvalidConfidenceReleases)
run("Multiple-hand refusal", e.testMultipleHandsDoNotControl)
run("Stall watchdog", e.testTrackingTimeoutPausesAndReleases)
run("Pause releases", e.testPauseReleasesWithoutDisabling)
run("Disable cannot auto-resume", e.testDisableReleasesAndCannotFistResume)
run("Fist one toggle per hold", e.testFistHoldPausesOnlyOnce)
run("Fist resume needs rearm", e.testReleasedFistCanResumeWithoutClick)
run("Right click debounce and disable", e.testRightClickIsDebouncedAndOptional)
run("Scroll freezes and resets", e.testScrollFreezesCursorAndResetsAnchor)
run("Scroll direction", e.testScrollDirectionCanReverse)
run("Open palm rests", e.testOpenPalmRestsAndRearmsBeforeClick)
run("Old frame refusal", e.testOutOfOrderFrameCannotClick)
run("Coordinate mapping", e.testMappingHasYFlipAndClamp)
run("Invalid settings recovery", e.testInvalidSettingsRecover)
run("Bad landmark refusal", e.testBadLandmarksAreNotReliable)
run("Pinch hysteresis", e.testPinchHysteresis)
run("Time-based smoothing", e.testSmoothingIsBoundedAndMovesTowardsTarget)
let c = CalibrationTests()
run("Two-corner calibration", c.testCalibratesTwoCornersAndMapsThem)
run("Calibration loss resets hold", c.testLossResetsDwell)
run("Calibration wrong/small rejection", c.testWrongPoseAndSmallRangeAreRejected)
run("Cancel calibration", c.testCancelKeepsNoNewRange)
run("Calibration movement resets hold", c.testMovementResetsDwell)
print("\n\(results.filter { $0["passed"] as? Bool == true }.count)/\(results.count) checks passed; \(assertions) assertions; \(failures) failures.")
if let path = ProcessInfo.processInfo.environment["GESTURE_MAC_CHECK_REPORT"],
   let data = try? JSONSerialization.data(withJSONObject: ["checks": results, "assertions": assertions, "failures": failures], options: [.prettyPrinted, .sortedKeys]) {
    try? data.write(to: URL(fileURLWithPath: path))
}
exit(failures == 0 ? 0 : 1)
