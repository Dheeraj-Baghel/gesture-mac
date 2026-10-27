import Foundation
import GestureCore

// No XCTest dependency: these same deterministic checks run on a CLT-only Mac.
final class ControlEngineTests {
    private func ready(_ engine: ControlEngine, at t: Double = 0) {
        _ = engine.enable(now: t)
        _ = engine.process(hand: Fixtures.hand(), now: t + 0.01)
        _ = engine.process(hand: Fixtures.hand(), now: t + 0.3)
    }
    private func pinched(_ engine: ControlEngine, at t: Double = 0.4) -> EngineOutput {
        _ = engine.process(hand: Fixtures.hand(.indexPinch), now: t)
        return engine.process(hand: Fixtures.hand(.indexPinch), now: t + 0.1)
    }
    private func hasDown(_ out: EngineOutput) -> Bool {
        out.actions.contains { if case .leftDown = $0 { return true }; return false }
    }
    private func hasUp(_ out: EngineOutput) -> Bool {
        out.actions.contains { if case .leftUp = $0 { return true }; return false }
    }
    private func hasMove(_ out: EngineOutput) -> Bool {
        out.actions.contains { if case .move = $0 { return true }; return false }
    }
    func testSyntheticPosesClassify() {
        for pose in [Gesture.point, .openPalm, .fist, .scroll, .indexPinch, .middlePinch] {
            let hand = Fixtures.hand(pose)
            expect(hand.isReliable(), "Reliable \(pose)")
            equal(Gesture.classify(hand), pose)
        }
    }
    func testPreviewNeverProducesInput() {
        let engine = ControlEngine()
        for (i, pose) in [Gesture.point, .indexPinch, .scroll, .middlePinch, .fist].enumerated() {
            let out = engine.process(hand: Fixtures.hand(pose), now: Double(i))
            expect(out.actions.isEmpty); expect(!out.enabled)
        }
    }
    func testPinchedStartupCannotClick() {
        let engine = ControlEngine(); _ = engine.enable(now: 0)
        expect(pinched(engine).actions.isEmpty)
        expect(engine.process(hand: Fixtures.hand(.indexPinch), now: 2).actions.isEmpty)
    }
    func testPointRequiresNeutralHold() {
        let engine = ControlEngine(); _ = engine.enable(now: 0)
        expect(!hasMove(engine.process(hand: Fixtures.hand(), now: 0.01)))
        expect(hasMove(engine.process(hand: Fixtures.hand(), now: 0.3)))
    }
    func testClickHasOneDownOneUp() {
        let engine = ControlEngine(); ready(engine)
        expect(hasDown(pinched(engine)))
        expect(!hasDown(engine.process(hand: Fixtures.hand(.indexPinch), now: 0.6)))
        expect(hasUp(engine.process(hand: Fixtures.hand(), now: 0.65)))
        expect(!hasUp(engine.process(hand: Fixtures.hand(), now: 0.7)))
    }
    func testShortPinchDoesNotClick() {
        let engine = ControlEngine(); ready(engine)
        _ = engine.process(hand: Fixtures.hand(.indexPinch), now: 0.4)
        let out = engine.process(hand: Fixtures.hand(), now: 0.44)
        expect(!hasUp(out)); expect(!hasDown(out))
    }
    func testTapPinchFreezesPointer() {
        let engine = ControlEngine(); ready(engine); let p = engine.pointer
        _ = pinched(engine)
        let out = engine.process(hand: Fixtures.hand(.indexPinch, x: 0.7), now: 0.65)
        expect(!hasMove(out)); equal(out.pointer, p)
    }
    func testLongPinchDragsAndReleases() {
        let engine = ControlEngine(); ready(engine); _ = pinched(engine)
        let out = engine.process(hand: Fixtures.hand(.indexPinch, x: 0.7), now: 0.85)
        expect(hasMove(out)); expect((out.pointer?.x ?? 0) > 0.5)
        expect(hasUp(engine.process(hand: Fixtures.hand(), now: 0.9)))
    }
    func testNoHandImmediatelyReleasesAndRequiresNewPoint() {
        let engine = ControlEngine(); ready(engine); _ = pinched(engine)
        expect(hasUp(engine.process(hand: nil, now: 0.6)))
        expect(!hasDown(pinched(engine, at: 0.7)))
    }
    func testInvalidConfidenceReleases() {
        let engine = ControlEngine(); ready(engine); _ = pinched(engine)
        var hand = Fixtures.hand(.indexPinch); hand.points[.wrist]?.confidence = 0.1
        expect(hasUp(engine.process(hand: hand, now: 0.6)))
    }
    func testMultipleHandsDoNotControl() {
        let engine = ControlEngine(); ready(engine); _ = pinched(engine)
        let out = engine.process(hand: nil, now: 0.6, issue: .multiple)
        expect(hasUp(out)); expect(out.message.contains("one hand"))
    }
    func testTrackingTimeoutPausesAndReleases() {
        let engine = ControlEngine(); ready(engine); _ = pinched(engine)
        let out = engine.tick(now: 1.3)
        expect(out.paused); expect(hasUp(out))
        expect(engine.process(hand: Fixtures.hand(), now: 1.4).actions.isEmpty)
    }
    func testPauseReleasesWithoutDisabling() {
        let engine = ControlEngine(); ready(engine); _ = pinched(engine)
        let out = engine.pause()
        expect(out.enabled); expect(out.paused); expect(hasUp(out))
    }
    func testDisableReleasesAndCannotFistResume() {
        let engine = ControlEngine(); ready(engine); _ = pinched(engine)
        expect(hasUp(engine.disable()))
        _ = engine.process(hand: Fixtures.hand(.fist), now: 1)
        let out = engine.process(hand: Fixtures.hand(.fist), now: 2)
        expect(!out.enabled); expect(out.actions.isEmpty)
    }
    func testFistHoldPausesOnlyOnce() {
        let engine = ControlEngine(); ready(engine)
        _ = engine.process(hand: Fixtures.hand(.fist), now: 0.5)
        expect(!engine.process(hand: Fixtures.hand(.fist), now: 0.9).paused)
        expect(engine.process(hand: Fixtures.hand(.fist), now: 1.21).paused)
        expect(engine.process(hand: Fixtures.hand(.fist), now: 3).paused)
    }
    func testReleasedFistCanResumeWithoutClick() {
        let engine = ControlEngine(); ready(engine)
        _ = engine.process(hand: Fixtures.hand(.fist), now: 0.5)
        _ = engine.process(hand: Fixtures.hand(.fist), now: 1.3)
        _ = engine.process(hand: Fixtures.hand(.point), now: 1.4)
        _ = engine.process(hand: Fixtures.hand(.point), now: 1.6)
        _ = engine.process(hand: Fixtures.hand(.fist), now: 1.7)
        let out = engine.process(hand: Fixtures.hand(.fist), now: 2.5)
        expect(!out.paused); expect(out.actions.isEmpty)
        expect(!hasDown(pinched(engine, at: 2.6)))
    }
    func testRightClickIsDebouncedAndOptional() {
        let engine = ControlEngine(); ready(engine)
        _ = engine.process(hand: Fixtures.hand(.middlePinch), now: 0.4)
        let out = engine.process(hand: Fixtures.hand(.middlePinch), now: 0.6)
        equal(out.actions.count, 1)
        expect(out.actions.contains { if case .rightClick = $0 { return true }; return false })
        expect(engine.process(hand: Fixtures.hand(.middlePinch), now: 1).actions.isEmpty)
        _ = engine.process(hand: Fixtures.hand(), now: 1.1)
        engine.settings.rightClickEnabled = false
        _ = engine.process(hand: Fixtures.hand(.middlePinch), now: 1.2)
        expect(engine.process(hand: Fixtures.hand(.middlePinch), now: 1.5).actions.isEmpty)
    }
    func testScrollFreezesCursorAndResetsAnchor() {
        let engine = ControlEngine(); ready(engine); let p = engine.pointer
        expect(engine.process(hand: Fixtures.hand(.scroll), now: 0.4).actions.isEmpty)
        let out = engine.process(hand: Fixtures.hand(.scroll, y: 0.52), now: 0.5)
        equal(out.pointer, p); expect(!hasMove(out)); equal(out.actions, [.scroll(-60)])
        _ = engine.process(hand: Fixtures.hand(), now: 0.6)
        expect(engine.process(hand: Fixtures.hand(.scroll, y: 0.65), now: 0.7).actions.isEmpty)
    }
    func testScrollDirectionCanReverse() {
        let engine = ControlEngine(); ready(engine); engine.settings.naturalScrolling = false
        _ = engine.process(hand: Fixtures.hand(.scroll), now: 0.4)
        let out = engine.process(hand: Fixtures.hand(.scroll, y: 0.5), now: 0.5)
        guard case .scroll(let amount) = out.actions.first else { expect(false, "No scroll"); return }
        expect(amount > 0)
    }
    func testOpenPalmRestsAndRearmsBeforeClick() {
        let engine = ControlEngine(); ready(engine); _ = pinched(engine)
        expect(hasUp(engine.process(hand: Fixtures.hand(.openPalm), now: 0.6)))
        expect(!hasDown(pinched(engine, at: 0.7)))
    }
    func testOutOfOrderFrameCannotClick() {
        let engine = ControlEngine(); ready(engine)
        _ = engine.process(hand: Fixtures.hand(.indexPinch), now: 1)
        expect(engine.process(hand: Fixtures.hand(.indexPinch), now: 0.9).actions.isEmpty)
    }
    func testMappingHasYFlipAndClamp() {
        let area = MappingArea(left: 0.2, right: 0.8, bottom: 0.2, top: 0.8)
        equal(area.map(Point(0.2, 0.8)), Point(0, 0))
        equal(area.map(Point(0.8, 0.2)), Point(1, 1))
        equal(area.map(Point(-1, 2)), Point(0, 0))
    }
    func testInvalidSettingsRecover() {
        var settings = Settings()
        settings.area.left = .nan; settings.smoothingSeconds = -.infinity; settings.scrollSensitivity = 1e9
        settings.sanitize(); expect(settings.area.isValid)
        equal(settings.smoothingSeconds, 0.065); equal(settings.scrollSensitivity, 3200)
    }
    func testBadLandmarksAreNotReliable() {
        var hand = Fixtures.hand(); hand.points[.indexTip]?.point.x = .nan
        expect(!hand.isReliable())
        hand = Fixtures.hand(); hand.points.removeValue(forKey: .thumbIP)
        expect(!hand.isReliable())
    }
    func testPinchHysteresis() {
        var hand = Fixtures.hand(.indexPinch); let tip = hand.points[.indexTip]!.point
        let offset = hand.palmWidth * 0.34 / hand.aspect
        hand.points[.thumbTip]?.point = Point(tip.x - offset, tip.y)
        expect(Gesture.classify(hand) != .indexPinch)
        equal(Gesture.classify(hand, previous: .indexPinch), .indexPinch)
    }
    func testSmoothingIsBoundedAndMovesTowardsTarget() {
        let engine = ControlEngine(); ready(engine); let initial = engine.pointer!
        let out = engine.process(hand: Fixtures.hand(.point, x: 0.7), now: 0.31)
        expect(out.pointer!.x > initial.x)
        expect(out.pointer!.x < engine.settings.area.map(Fixtures.hand(.point, x: 0.7).palmCenter).x)
    }
}
