import Foundation
import GestureCore

final class CalibrationTests {
    func testCalibratesTwoCornersAndMapsThem() {
        let c = Calibration(); c.start()
        for i in 0...14 { c.process(hand: Fixtures.hand(.point, x: 0.25, y: 0.7), now: Double(i) * 0.1) }
        equal(c.stage, .lowerRight)
        for i in 15...29 { c.process(hand: Fixtures.hand(.point, x: 0.75, y: 0.3), now: Double(i) * 0.1) }
        equal(c.stage, .complete); expect(c.result != nil)
        guard let area = c.result else { return }
        let first = area.map(Fixtures.hand(.point, x: 0.25, y: 0.7).palmCenter)
        expect(abs(first.x) < 0.00001 && abs(first.y) < 0.00001)
        expect(abs(area.map(Fixtures.hand(.point, x: 0.75, y: 0.3).palmCenter).x - 1) < 0.00001)
    }
    func testLossResetsDwell() {
        let c = Calibration(); c.start()
        c.process(hand: Fixtures.hand(.point, x: 0.25, y: 0.7), now: 0)
        c.process(hand: Fixtures.hand(.point, x: 0.25, y: 0.7), now: 0.8)
        c.process(hand: nil, now: 0.9)
        equal(c.progress, 0)
        c.process(hand: Fixtures.hand(.point, x: 0.25, y: 0.7), now: 1)
        equal(c.stage, .upperLeft)
    }
    func testWrongPoseAndSmallRangeAreRejected() {
        let c = Calibration(); c.start()
        for i in 0...14 { c.process(hand: Fixtures.hand(.fist), now: Double(i) * 0.1) }
        equal(c.stage, .upperLeft)
        for i in 15...29 { c.process(hand: Fixtures.hand(.point, x: 0.4, y: 0.55), now: Double(i) * 0.1) }
        equal(c.stage, .lowerRight)
        for i in 30...45 { c.process(hand: Fixtures.hand(.point, x: 0.5, y: 0.45), now: Double(i) * 0.1) }
        expect(c.result == nil); equal(c.stage, .lowerRight)
    }
    func testCancelKeepsNoNewRange() {
        let c = Calibration(); c.start(); c.cancel()
        equal(c.stage, .idle); expect(c.result == nil); expect(!c.inProgress)
    }
    func testMovementResetsDwell() {
        let c = Calibration(); c.start()
        c.process(hand: Fixtures.hand(.point, x: 0.25, y: 0.7), now: 0)
        c.process(hand: Fixtures.hand(.point, x: 0.35, y: 0.6), now: 1)
        equal(c.progress, 0); equal(c.stage, .upperLeft)
    }
}
