import Foundation

// Camera-space coordinates are normalized, mirrored, and Y-up. Mouse-space
// coordinates are normalized and Y-down. Aspect is used only for geometry;
// distances/angles must not treat a wide camera image as a square.
public struct Point: Equatable, Codable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public func distance(to other: Point, aspect: Double = 1) -> Double {
        hypot((x - other.x) * aspect, y - other.y)
    }
    public func clamped() -> Point { Point(min(1, max(0, x)), min(1, max(0, y))) }
}

public enum Joint: String, CaseIterable, Codable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

public struct Landmark: Equatable {
    public var point: Point
    public var confidence: Double
    public init(_ point: Point, confidence: Double = 1) {
        self.point = point; self.confidence = confidence
    }
}

public struct Hand: Equatable {
    public var points: [Joint: Landmark]
    public var aspect: Double
    public init(points: [Joint: Landmark], aspect: Double = 4.0 / 3.0) {
        self.points = points; self.aspect = aspect
    }
    public func isReliable(threshold: Double = 0.4) -> Bool {
        guard aspect.isFinite, aspect > 0 else { return false }
        return Joint.allCases.allSatisfy {
            guard let p = points[$0] else { return false }
            return p.confidence.isFinite && p.confidence >= threshold &&
                p.point.x.isFinite && p.point.y.isFinite &&
                (0...1).contains(p.point.x) && (0...1).contains(p.point.y)
        } && palmWidth > 0.045
    }
    public var palmCenter: Point {
        let joints: [Joint] = [.wrist, .indexMCP, .middleMCP, .littleMCP]
        let p = joints.compactMap { points[$0]?.point }
        guard p.count == joints.count else { return Point(0.5, 0.5) }
        return Point(p.map(\.x).reduce(0, +) / 4, p.map(\.y).reduce(0, +) / 4)
    }
    public var palmWidth: Double {
        distance(.indexMCP, .littleMCP)
    }
    public func distance(_ a: Joint, _ b: Joint) -> Double {
        guard let a = points[a]?.point, let b = points[b]?.point else { return 0 }
        return a.distance(to: b, aspect: aspect)
    }
    public func pinchRatio(_ tip: Joint) -> Double {
        guard palmWidth > 0 else { return .infinity }
        return distance(.thumbTip, tip) / palmWidth
    }
    public func angle(_ a: Joint, _ b: Joint, _ c: Joint) -> Double {
        guard let a = points[a]?.point, let b = points[b]?.point,
              let c = points[c]?.point else { return 0 }
        let u = Point((a.x - b.x) * aspect, a.y - b.y)
        let v = Point((c.x - b.x) * aspect, c.y - b.y)
        let norm = hypot(u.x, u.y) * hypot(v.x, v.y)
        guard norm > 0.000001 else { return 0 }
        return acos(min(1, max(-1, (u.x * v.x + u.y * v.y) / norm))) * 180 / .pi
    }
    public func extended(_ mcp: Joint, _ pip: Joint, _ dip: Joint, _ tip: Joint) -> Bool {
        angle(mcp, pip, dip) > 150 && angle(pip, dip, tip) > 140 &&
            distance(.wrist, tip) > distance(.wrist, pip) * 1.1
    }
    public func curled(_ mcp: Joint, _ pip: Joint, _ dip: Joint, _ tip: Joint) -> Bool {
        angle(mcp, pip, dip) < 145 &&
            distance(.wrist, tip) < distance(.wrist, pip) * 1.08
    }
}

public struct MappingArea: Codable, Equatable {
    public var left: Double
    public var right: Double
    public var bottom: Double
    public var top: Double
    public init(left: Double = 0.17, right: Double = 0.83,
                bottom: Double = 0.17, top: Double = 0.83) {
        self.left = left; self.right = right; self.bottom = bottom; self.top = top
    }
    public var isValid: Bool {
        [left, right, bottom, top].allSatisfy { $0.isFinite && (0...1).contains($0) } &&
            right - left >= 0.25 && top - bottom >= 0.25
    }
    public func map(_ p: Point) -> Point {
        guard isValid else { return MappingArea().map(p) }
        return Point((p.x - left) / (right - left),
                     1 - (p.y - bottom) / (top - bottom)).clamped()
    }
}

public struct Settings: Codable, Equatable {
    public var area = MappingArea()
    // Time-based smoothing, rather than per-frame interpolation.
    public var smoothingSeconds: Double = 0.065
    public var scrollSensitivity: Double = 1600
    public var naturalScrolling: Bool = true
    public var rightClickEnabled: Bool = true
    public init() {}
    public mutating func sanitize() {
        if !area.isValid { area = MappingArea() }
        if !smoothingSeconds.isFinite { smoothingSeconds = 0.065 }
        smoothingSeconds = min(0.18, max(0.02, smoothingSeconds))
        if !scrollSensitivity.isFinite { scrollSensitivity = 1600 }
        scrollSensitivity = min(3200, max(400, scrollSensitivity))
    }
}

public enum Gesture: String, Equatable {
    case point = "Point"
    case indexPinch = "Click / drag"
    case middlePinch = "Right click"
    case scroll = "Two-finger scroll"
    case fist = "Fist: pause / resume"
    case openPalm = "Open palm"
    case unknown = "Relax / reposition"

    public static func classify(_ hand: Hand, previous: Gesture = .unknown) -> Gesture {
        guard hand.isReliable() else { return .unknown }
        let index = hand.extended(.indexMCP, .indexPIP, .indexDIP, .indexTip)
        let middle = hand.extended(.middleMCP, .middlePIP, .middleDIP, .middleTip)
        let ring = hand.extended(.ringMCP, .ringPIP, .ringDIP, .ringTip)
        let little = hand.extended(.littleMCP, .littlePIP, .littleDIP, .littleTip)
        let curled = hand.curled(.indexMCP, .indexPIP, .indexDIP, .indexTip) &&
            hand.curled(.middleMCP, .middlePIP, .middleDIP, .middleTip) &&
            hand.curled(.ringMCP, .ringPIP, .ringDIP, .ringTip) &&
            hand.curled(.littleMCP, .littlePIP, .littleDIP, .littleTip)
        // A fist must never start a click just because thumb and fingertips meet.
        if curled { return .fist }
        if index && middle && ring && little { return .openPalm }
        let indexLimit = previous == .indexPinch ? 0.42 : 0.27
        let middleLimit = previous == .middlePinch ? 0.42 : 0.27
        if !middle && !ring && !little && hand.pinchRatio(.indexTip) < indexLimit {
            return .indexPinch
        }
        if index && !ring && !little && hand.pinchRatio(.middleTip) < middleLimit {
            return .middlePinch
        }
        if index && middle && !ring && !little { return .scroll }
        if index && !middle && !ring && !little { return .point }
        return .unknown
    }
}
