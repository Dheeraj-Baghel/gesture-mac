import GestureCore

// Synthetic 2-D poses exercise math and state transitions, NOT Apple Vision
// recognition accuracy. These fixtures are never shown as a real camera feed.
enum Fixtures {
    static let aspect = 4.0 / 3.0
    static func hand(_ gesture: Gesture = .point, x: Double = 0.5, y: Double = 0.48) -> Hand {
        var p: [Joint: Landmark] = [:]
        func add(_ joint: Joint, _ px: Double, _ py: Double) {
            p[joint] = Landmark(Point(x + px, y + py))
        }
        add(.wrist, 0, -0.16)
        let fingers: [(Joint, Joint, Joint, Joint, Double)] = [
            (.indexMCP, .indexPIP, .indexDIP, .indexTip, -0.08),
            (.middleMCP, .middlePIP, .middleDIP, .middleTip, -0.025),
            (.ringMCP, .ringPIP, .ringDIP, .ringTip, 0.035),
            (.littleMCP, .littlePIP, .littleDIP, .littleTip, 0.09)
        ]
        for (mcp, pip, dip, tip, fx) in fingers {
            let extended = gesture == .openPalm ||
                (mcp == .indexMCP && gesture != .fist) ||
                (mcp == .middleMCP && gesture == .scroll)
            add(mcp, fx, -0.015)
            if extended {
                add(pip, fx, 0.09); add(dip, fx, 0.155); add(tip, fx, 0.21)
            } else {
                add(pip, fx, 0.065); add(dip, fx + 0.012, 0.018); add(tip, fx + 0.01, -0.065)
            }
        }
        add(.thumbCMC, -0.09, -0.1)
        add(.thumbMP, -0.135, -0.065)
        add(.thumbIP, -0.175, -0.025)
        add(.thumbTip, -0.2, 0.015)
        if gesture == .indexPinch {
            // Bent but not fully curled index: thumb tip touches its tip.
            add(.indexPIP, -0.08, 0.09)
            add(.indexDIP, -0.1, 0.13)
            add(.indexTip, -0.13, 0.09)
            add(.thumbTip, -0.135, 0.09)
        }
        if gesture == .middlePinch {
            add(.middlePIP, -0.025, 0.09)
            add(.middleDIP, -0.045, 0.13)
            add(.middleTip, -0.075, 0.09)
            add(.thumbTip, -0.08, 0.09)
        }
        return Hand(points: p, aspect: aspect)
    }
}
