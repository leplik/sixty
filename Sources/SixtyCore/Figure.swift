import CoreGraphics
import Foundation

// A stick figure that demonstrates each exercise on the lock screen.
//
// Everything lives in a 1×1 box with y growing upwards and the floor at `FigureMetrics.ground`.
// An animation is a function of time that returns a `Pose` (root position + joint angles), usually built from
// keyframes. `FigureSolver` turns a pose into joint positions with forward kinematics, so bones never stretch.
// Two-bone IK only ever produces angles, which are then blended with the keyframed ones and fed to the same FK.
// After the legs are placed, the whole body is moved so that the lowest point of a foot touches the floor.

// MARK: - Output

public enum FigureProjection: Sendable, Equatable {
    /// The figure faces +x and shows its left side, so its left limbs are the near ones.
    case side
    /// The figure faces the viewer, so its left side is at +x.
    case front
}

public enum FigureSide: Sendable, CaseIterable {
    case left
    case right

    /// Mirrors front-view angles, so that a positive angle always means "outwards" on either side.
    var sign: Double { self == .left ? 1 : -1 }
}

/// One value per body side.
public struct Sides<Value> {
    public var left: Value
    public var right: Value

    public init(left: Value, right: Value) {
        self.left = left
        self.right = right
    }

    public init(_ both: Value) {
        self.init(left: both, right: both)
    }

    public subscript(side: FigureSide) -> Value {
        get { side == .left ? left : right }
        set {
            switch side {
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }

    mutating func both(_ change: (inout Value) -> Void) {
        change(&left)
        change(&right)
    }
}

extension Sides: Sendable where Value: Sendable {}
extension Sides: Equatable where Value: Equatable {}

/// Proportions in box units. A standing figure is 0.72 tall; raised hands reach about 0.94.
public enum FigureMetrics {
    public static let ground = 0.06
    public static let headRadius = 0.06
    public static let eyeRadius = 0.0085
    /// From the pelvis to the base of the neck, in three equal segments that can curl (`Pose.spine`).
    public static let torso = 0.23
    public static var spineSegment: Double { torso / 3 }
    /// From the base of the neck to the centre of the head.
    public static let neck = 0.085
    public static let upperArm = 0.135
    /// Includes the hand.
    public static let forearm = 0.15
    public static let thigh = 0.18
    public static let shin = 0.17
    /// Side view: the foot runs from the heel, behind the ankle, to the toes in front of it.
    public static let heel = 0.016
    public static let toe = 0.052
    /// Front view: the foot is a short tick pointing outwards from the ankle.
    public static let frontToe = 0.034
    /// Front view: half the shoulder and hip bars. Twists foreshorten them, so they are projections, not bones.
    public static let shoulderHalfWidth = 0.064
    public static let hipHalfWidth = 0.04
    /// Side view: the shoulder joint sits a little below the base of the neck.
    static let shoulderDrop = 0.012
    static var leg: Double { thigh + shin }
}

/// Joint positions in the figure box.
public struct Skeleton: Sendable, Equatable {
    public var pelvis = CGPoint.zero
    /// The joints between the three spine segments: the top of the lumbar spine and the middle of the back.
    public var lowerBack = CGPoint.zero
    public var upperBack = CGPoint.zero
    public var neckBase = CGPoint.zero
    /// The centre of the head.
    public var head = CGPoint.zero
    /// The top of the head: tilts with it.
    public var crown = CGPoint.zero
    public var shoulders = Sides(CGPoint.zero)
    public var elbows = Sides(CGPoint.zero)
    public var hands = Sides(CGPoint.zero)
    public var hips = Sides(CGPoint.zero)
    public var knees = Sides(CGPoint.zero)
    public var ankles = Sides(CGPoint.zero)
    public var heels = Sides(CGPoint.zero)
    public var toes = Sides(CGPoint.zero)

    public var points: [CGPoint] {
        [pelvis, neckBase, head, crown]
            + [shoulders, elbows, hands, hips, knees, ankles, heels, toes].flatMap { [$0.left, $0.right] }
            + [lowerBack, upperBack]
    }

    mutating func translate(by offset: CGVector) {
        func move(_ pair: inout Sides<CGPoint>) {
            pair.both { $0 = $0 + offset }
        }
        pelvis = pelvis + offset
        lowerBack = lowerBack + offset
        upperBack = upperBack + offset
        neckBase = neckBase + offset
        head = head + offset
        crown = crown + offset
        move(&shoulders)
        move(&elbows)
        move(&hands)
        move(&hips)
        move(&knees)
        move(&ankles)
        move(&heels)
        move(&toes)
    }

    func point(_ joint: TrailJoint) -> CGPoint {
        switch joint {
        case .pelvis: pelvis
        case .head: head
        case .crown: crown
        case .shoulder(let side): shoulders[side]
        case .hand(let side): hands[side]
        case .knee(let side): knees[side]
        case .heel(let side): heels[side]
        }
    }
}

/// A joint whose recent path is drawn behind the figure to show where it moves.
public enum TrailJoint: Sendable, Equatable {
    case pelvis
    case head
    case crown
    case shoulder(FigureSide)
    case hand(FigureSide)
    case knee(FigureSide)
    case heel(FigureSide)
}

/// Scenery and hints around the figure: the floor, a desk, a window, a glass, a gaze line.
public struct FigureProp: Sendable, Equatable {
    public enum Shape: Sendable, Equatable {
        case line([CGPoint])
        /// A closed outline.
        case loop([CGPoint])
        /// A filled polygon.
        case area([CGPoint])
        case dot(CGPoint, radius: Double)
    }

    public enum Ink: Sendable, Equatable {
        /// The floor and distant scenery: faint.
        case ground
        /// Furniture: half-tone.
        case object
        /// Something the figure holds: as bright as the body.
        case body
        case accent
    }

    public var shape: Shape
    public var ink: Ink
    public var opacity: Double
    /// Dash phase in box units for a dashed line; nil draws it solid.
    public var dash: Double?
    /// Drawn after the figure, with a thin outline in the background colour so it stays visible on the body.
    public var inFront: Bool

    public init(_ shape: Shape, ink: Ink, opacity: Double = 1, dash: Double? = nil, inFront: Bool = false) {
        self.shape = shape
        self.ink = ink
        self.opacity = opacity
        self.dash = dash
        self.inFront = inFront
    }

    public var points: [CGPoint] {
        switch shape {
        case .line(let points), .loop(let points), .area(let points): points
        case .dot(let center, let radius):
            [center + CGVector(dx: -radius, dy: -radius), center + CGVector(dx: radius, dy: radius)]
        }
    }
}

/// Everything needed to draw one moment of an animation.
public struct FigureFrame: Sendable, Equatable {
    public var projection: FigureProjection
    public var skeleton: Skeleton
    /// Below 0 a limb is behind the torso: drawn first and dimmed. -1 is fully behind.
    public var armDepth: Sides<Double>
    public var legDepth: Sides<Double>
    public var eyes: [CGPoint]
    public var props: [FigureProp]
    /// Recent positions of the joints that carry the motion, newest first.
    public var trails: [[CGPoint]]
    /// Trails are normally drawn behind the figure; some joints move where the body would hide them.
    public var trailsInFront = false
}

// MARK: - Pose

/// What a hand reaches for. Offsets are in box units; in the front view `dx` points outwards.
enum Reach: Sendable, Equatable {
    case world(CGPoint)
    /// Relative to the hip on the same side.
    case hip(CGVector)
    /// Relative to the centre of the head.
    case head(CGVector)
    /// A point on the thigh on the same side (0 = hip, 1 = knee) plus an offset.
    case thigh(Double, CGVector)
    /// Relative to the knee of the given side, so both hands can hold one knee.
    case knee(FigureSide, CGVector)
    /// Relative to the lower back, in the frame of the lumbar segment: x forward, y up along the spine.
    case back(CGVector)
}

struct Arm: Sendable, Equatable {
    /// Relative to the torso: 0 hangs along it, + swings forward (side view) or outward (front view), π is overhead.
    var shoulder = 0.0
    /// Side view: flexion, never negative; the forearm folds forward. Front view: + folds a hanging forearm towards
    /// the midline. The fold turns with the arm, so a raised arm needs a negative value to bend towards the head.
    var elbow = 0.0
    /// Moves the shoulder joint in the torso frame (x forward or outward, y up): shrugs and shoulder rolls.
    var girdle = CGVector.zero
    var depth = 0.0
    var reach: Reach?
    /// 0 uses the angles above, 1 puts the hand on `reach`; values in between blend the angles.
    var reachWeight = 0.0
}

/// How the spine curls, in radians. + rounds it forward (side view: a cat back, a roll-down), − arches it.
struct Spine: Sendable, Equatable {
    /// Between the lumbar segment and the middle of the back.
    var lower = 0.0
    /// Between the middle of the back and the upper back.
    var upper = 0.0
}

struct Leg: Sendable, Equatable {
    /// The thigh from straight down, in the world: + forward (side view) or outward (front view).
    var hip = 0.0
    /// Flexion, never negative: the shin folds backward (side view) or the knee points outward (front view).
    var knee = 0.0
    /// The foot in the world: 0 is flat, + lifts the heel (toes down).
    var foot = 0.0
    var depth = 0.0
    /// An ankle position the leg reaches with IK, weighted like `Arm.reach`.
    var plant: CGPoint?
    var plantWeight = 0.0
}

/// Root position and joint angles, in radians. The solver may lift or lower the root to keep a foot on the floor.
struct Pose: Sendable, Equatable {
    /// The pelvis.
    var root = CGPoint(x: 0.5, y: FigureMetrics.ground + FigureMetrics.leg)
    /// The torso from vertical: + forward (side view) or towards +x (front view). With a curled spine this is the
    /// lowest (lumbar) segment, which also shows the tilt of the pelvis.
    var lean = 0.0
    /// Bends between the spine segments, added on top of `lean`.
    var spine = Spine()
    /// The head relative to the top of the spine, same sign as `lean`.
    var neck = 0.0
    /// Front view: turns the head towards +x; only the eyes show it.
    var headYaw = 0.0
    /// Front view: turns the shoulders about the spine, foreshortening the shoulder bar.
    var twist = 0.0
    /// Front view: + raises the hip at +x.
    var pelvisTilt = 0.0
    var arms = Sides(Arm())
    var legs = Sides(Leg())
    /// A free channel for the animation's props, for example the tilt of a glass.
    var prop = 0.0

    /// The direction of the top spine segment: the chest. Shoulders, arms and head hang off it.
    var chest: Double { lean + spine.lower + spine.upper }

    func with(_ change: (inout Pose) -> Void) -> Pose {
        var copy = self
        change(&copy)
        return copy
    }

    /// Standing relaxed, seen from the side: the far limbs are behind the body.
    static let side = Pose().with { pose in
        pose.arms.both {
            $0.shoulder = 0.06
            $0.elbow = 0.22
        }
        pose.legs.both {
            $0.hip = 0.015
            $0.knee = 0.03
        }
        pose.arms.left.depth = 1
        pose.legs.left.depth = 1
        pose.arms.right.depth = -1
        pose.legs.right.depth = -1
    }

    /// Standing relaxed, facing the viewer, feet a little apart.
    static let front = Pose().with { pose in
        pose.arms.both {
            $0.shoulder = 0.13
            $0.elbow = 0.12
        }
        pose.legs.both { $0.hip = 0.06 }
    }
}

// MARK: - Keyframes

protocol Blendable {
    static func blend(_ from: Self, _ to: Self, _ t: Double) -> Self
}

extension Double: Blendable {
    static func blend(_ from: Double, _ to: Double, _ t: Double) -> Double {
        from + (to - from) * t
    }
}

extension CGPoint: Blendable {
    static func blend(_ from: CGPoint, _ to: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: Double.blend(from.x, to.x, t), y: Double.blend(from.y, to.y, t))
    }
}

extension CGVector: Blendable {
    static func blend(_ from: CGVector, _ to: CGVector, _ t: Double) -> CGVector {
        CGVector(dx: Double.blend(from.dx, to.dx, t), dy: Double.blend(from.dy, to.dy, t))
    }
}

/// A missing value takes the other one: pair a nil target with weight 0 to fade IK in or out smoothly.
extension Optional: Blendable where Wrapped: Blendable {
    static func blend(_ from: Wrapped?, _ to: Wrapped?, _ t: Double) -> Wrapped? {
        guard let from else { return to }
        guard let to else { return from }
        return Wrapped.blend(from, to, t)
    }
}

extension Sides: Blendable where Value: Blendable {
    static func blend(_ from: Sides, _ to: Sides, _ t: Double) -> Sides {
        Sides(left: .blend(from.left, to.left, t), right: .blend(from.right, to.right, t))
    }
}

extension Reach: Blendable {
    static func blend(_ from: Reach, _ to: Reach, _ t: Double) -> Reach {
        switch (from, to) {
        case (.world(let a), .world(let b)): .world(.blend(a, b, t))
        case (.hip(let a), .hip(let b)): .hip(.blend(a, b, t))
        case (.head(let a), .head(let b)): .head(.blend(a, b, t))
        case (.thigh(let fa, let a), .thigh(let fb, let b)): .thigh(.blend(fa, fb, t), .blend(a, b, t))
        case (.knee(let side, let a), .knee(let other, let b)) where side == other: .knee(side, .blend(a, b, t))
        case (.back(let a), .back(let b)): .back(.blend(a, b, t))
        default: t < 0.5 ? from : to
        }
    }
}

extension Arm: Blendable {
    static func blend(_ from: Arm, _ to: Arm, _ t: Double) -> Arm {
        Arm(
            shoulder: .blend(from.shoulder, to.shoulder, t),
            elbow: .blend(from.elbow, to.elbow, t),
            girdle: .blend(from.girdle, to.girdle, t),
            depth: .blend(from.depth, to.depth, t),
            reach: .blend(from.reach, to.reach, t),
            reachWeight: .blend(from.reachWeight, to.reachWeight, t)
        )
    }
}

extension Spine: Blendable {
    static func blend(_ from: Spine, _ to: Spine, _ t: Double) -> Spine {
        Spine(lower: .blend(from.lower, to.lower, t), upper: .blend(from.upper, to.upper, t))
    }
}

extension Leg: Blendable {
    static func blend(_ from: Leg, _ to: Leg, _ t: Double) -> Leg {
        Leg(
            hip: .blend(from.hip, to.hip, t),
            knee: .blend(from.knee, to.knee, t),
            foot: .blend(from.foot, to.foot, t),
            depth: .blend(from.depth, to.depth, t),
            plant: .blend(from.plant, to.plant, t),
            plantWeight: .blend(from.plantWeight, to.plantWeight, t)
        )
    }
}

extension Pose: Blendable {
    static func blend(_ from: Pose, _ to: Pose, _ t: Double) -> Pose {
        Pose(
            root: .blend(from.root, to.root, t),
            lean: .blend(from.lean, to.lean, t),
            spine: .blend(from.spine, to.spine, t),
            neck: .blend(from.neck, to.neck, t),
            headYaw: .blend(from.headYaw, to.headYaw, t),
            twist: .blend(from.twist, to.twist, t),
            pelvisTilt: .blend(from.pelvisTilt, to.pelvisTilt, t),
            arms: .blend(from.arms, to.arms, t),
            legs: .blend(from.legs, to.legs, t),
            prop: .blend(from.prop, to.prop, t)
        )
    }
}

enum Easing: Sendable {
    case linear
    /// Starts and stops gently (sine).
    case inOut
    /// Starts gently, ends at full speed: the first of several moves that run on into each other.
    case `in`
    /// Starts at full speed, stops gently: the last of them.
    case out

    func callAsFunction(_ x: Double) -> Double {
        switch self {
        case .linear: x
        case .inOut: 0.5 - 0.5 * cos(.pi * x)
        case .in: 1 - cos(.pi / 2 * x)
        case .out: sin(.pi / 2 * x)
        }
    }
}

/// Hold `value` for `hold` seconds, then move to the next key over `move` seconds.
struct Key<Value: Blendable & Sendable>: Sendable {
    var value: Value
    var hold: TimeInterval
    var move: TimeInterval
    var easing: Easing

    init(_ value: Value, hold: TimeInterval = 0, move: TimeInterval, _ easing: Easing = .inOut) {
        self.value = value
        self.hold = hold
        self.move = move
        self.easing = easing
    }
}

/// A looping sequence of keys. After the last key it moves back to the first.
struct Track<Value: Blendable & Sendable>: Sendable {
    let keys: [Key<Value>]
    let period: TimeInterval

    init(_ keys: [Key<Value>]) {
        precondition(!keys.isEmpty)
        self.keys = keys
        period = keys.reduce(0) { $0 + $1.hold + $1.move }
    }

    func callAsFunction(_ time: TimeInterval) -> Value {
        var t = time.wrapped(period)
        for (index, key) in keys.enumerated() {
            if t < key.hold { return key.value }
            t -= key.hold
            if t < key.move {
                let next = keys[(index + 1) % keys.count].value
                return .blend(key.value, next, key.easing(t / key.move))
            }
            t -= key.move
        }
        return keys[0].value
    }
}

extension Double {
    /// The time within a loop of `period` seconds; also correct for negative times.
    func wrapped(_ period: Double) -> Double {
        guard period > 0 else { return 0 }
        let r = truncatingRemainder(dividingBy: period)
        return r < 0 ? r + period : r
    }
}

// MARK: - Solver

/// Turns a pose into joint positions. See the comment at the top of the file.
enum FigureSolver {
    private typealias M = FigureMetrics

    /// `anchor` keeps the near toe at this x, so a planted foot does not slide while the angles change.
    static func solve(_ pose: Pose, _ projection: FigureProjection, anchor: Double?) -> Skeleton {
        let front = projection == .front
        let chest = pose.chest
        let up = CGVector(dx: sin(chest), dy: cos(chest))
        let across = CGVector(dx: cos(chest), dy: -sin(chest))
        let headAngle = chest + pose.neck
        var s = Skeleton()
        s.pelvis = pose.root
        let middle = pose.lean + pose.spine.lower
        s.lowerBack = s.pelvis + CGVector(dx: sin(pose.lean), dy: cos(pose.lean)) * M.spineSegment
        s.upperBack = s.lowerBack + CGVector(dx: sin(middle), dy: cos(middle)) * M.spineSegment
        s.neckBase = s.upperBack + up * M.spineSegment
        let headUp = CGVector(dx: sin(headAngle), dy: cos(headAngle))
        s.head = s.neckBase + headUp * M.neck
        s.crown = s.head + headUp * M.headRadius

        let hipAxis = CGVector(dx: cos(pose.pelvisTilt), dy: sin(pose.pelvisTilt))
        for side in FigureSide.allCases {
            let girdle = pose.arms[side].girdle
            if front {
                let m = side.sign
                let half = M.shoulderHalfWidth * cos(pose.twist) + girdle.dx
                s.shoulders[side] = s.neckBase + across * (m * half) + up * girdle.dy
                // The hips follow a quarter of the shoulder twist.
                s.hips[side] = s.pelvis + hipAxis * (m * M.hipHalfWidth * cos(pose.twist * 0.25))
            } else {
                s.shoulders[side] = s.neckBase + across * girdle.dx + up * (girdle.dy - M.shoulderDrop)
                s.hips[side] = s.pelvis
            }
            placeLeg(side, pose.legs[side], front: front, in: &s)
        }

        let contacts = [s.heels.left, s.heels.right, s.toes.left, s.toes.right].map(\.y)
        var shift = CGVector(dx: 0, dy: M.ground - (contacts.min() ?? M.ground))
        if let anchor { shift.dx = anchor - s.toes.left.x }
        s.translate(by: shift)

        // Arms come last: their targets may hang off the hips, the thighs or the head.
        for side in FigureSide.allCases {
            placeArm(side, pose.arms[side], pose: pose, front: front, in: &s)
        }
        return s
    }

    static func eyes(_ pose: Pose, _ projection: FigureProjection, head: CGPoint) -> [CGPoint] {
        let angle = pose.chest + pose.neck
        let up = CGVector(dx: sin(angle), dy: cos(angle))
        let across = CGVector(dx: cos(angle), dy: -sin(angle))
        let r = M.headRadius
        switch projection {
        case .side:
            return [head + across * (0.45 * r) + up * (0.12 * r)]
        case .front:
            let shift = 0.5 * sin(pose.headYaw)
            let spread = 0.34 * cos(pose.headYaw)
            return [-1.0, 1.0].map { head + across * ((shift + $0 * spread) * r) + up * (0.1 * r) }
        }
    }

    private static func placeLeg(_ side: FigureSide, _ leg: Leg, front: Bool, in s: inout Skeleton) {
        let m = front ? side.sign : 1
        let hip = s.hips[side]
        var thigh = m * leg.hip
        var bend = -m * leg.knee
        if let plant = leg.plant, leg.plantWeight > 0 {
            let (knee, ankle) = twoBone(from: hip, to: plant, M.thigh, M.shin, bend: m)
            (thigh, bend) = blend(thigh, bend, towards: hip, knee, ankle, leg.plantWeight)
        }
        s.knees[side] = hip + direction(thigh) * M.thigh
        s.ankles[side] = s.knees[side] + direction(thigh + bend) * M.shin
        let foot = CGVector(dx: m * cos(leg.foot), dy: -sin(leg.foot))
        s.heels[side] = s.ankles[side] - foot * (front ? 0 : M.heel)
        s.toes[side] = s.ankles[side] + foot * (front ? M.frontToe : M.toe)
    }

    private static func placeArm(_ side: FigureSide, _ arm: Arm, pose: Pose, front: Bool, in s: inout Skeleton) {
        let m = front ? side.sign : 1
        let fold = front ? -m : 1
        let shoulder = s.shoulders[side]
        var upper = m * arm.shoulder - pose.chest
        var bend = fold * arm.elbow
        if let reach = arm.reach, arm.reachWeight > 0 {
            let target = point(for: reach, side: side, mirror: m, lumbar: pose.lean, in: s)
            let (elbow, hand) = twoBone(from: shoulder, to: target, M.upperArm, M.forearm, bend: -fold)
            (upper, bend) = blend(upper, bend, towards: shoulder, elbow, hand, arm.reachWeight)
        }
        s.elbows[side] = shoulder + direction(upper) * M.upperArm
        s.hands[side] = s.elbows[side] + direction(upper + bend) * M.forearm
    }

    /// Blends a limb's angles towards an IK solution. The parent bone and the bend of the middle joint are blended
    /// separately and without wrapping, so a knee or an elbow never swings through the wrong side on the way,
    /// and an arm raised past horizontal does not take the short way round. The parent angle comes straight
    /// from `atan2`, so IK targets should not sit straight above the root, where it wraps.
    private static func blend(
        _ parent: Double,
        _ bend: Double,
        towards root: CGPoint,
        _ middle: CGPoint,
        _ end: CGPoint,
        _ weight: Double
    ) -> (parent: Double, bend: Double) {
        let ikParent = angle(of: middle - root)
        let ikBend = remainder(angle(of: end - middle) - ikParent, 2 * .pi)
        return (.blend(parent, ikParent, weight), .blend(bend, ikBend, weight))
    }

    private static func point(
        for reach: Reach,
        side: FigureSide,
        mirror m: Double,
        lumbar: Double,
        in s: Skeleton
    ) -> CGPoint {
        switch reach {
        case .world(let point):
            point
        case .hip(let offset):
            s.hips[side] + CGVector(dx: m * offset.dx, dy: offset.dy)
        case .head(let offset):
            s.head + CGVector(dx: m * offset.dx, dy: offset.dy)
        case .thigh(let fraction, let offset):
            s.hips[side] + (s.knees[side] - s.hips[side]) * fraction + CGVector(dx: m * offset.dx, dy: offset.dy)
        case .knee(let knee, let offset):
            s.knees[knee] + CGVector(dx: m * offset.dx, dy: offset.dy)
        case .back(let offset):
            s.lowerBack + CGVector(dx: cos(lumbar), dy: -sin(lumbar)) * offset.dx
                + CGVector(dx: sin(lumbar), dy: cos(lumbar)) * offset.dy
        }
    }

    /// Two-bone IK in the plane. `bend` is the sign of cross(end - root, middle - root): the side the middle
    /// joint (knee, elbow) goes to. An unreachable target gets a straight limb pointing at it.
    static func twoBone(
        from root: CGPoint,
        to target: CGPoint,
        _ a: Double,
        _ b: Double,
        bend: Double
    ) -> (middle: CGPoint, end: CGPoint) {
        let v = target - root
        let distance = v.length
        let u = distance > 1e-9 ? v * (1 / distance) : CGVector(dx: 0, dy: -1)
        let reach = min(max(distance, abs(a - b) + 1e-6), a + b - 1e-9)
        let cosine = (a * a + reach * reach - b * b) / (2 * a * reach)
        let turn = acos(min(1, max(-1, cosine))) * bend
        let middle = root + u.rotated(by: turn) * a
        return (middle, root + u * reach)
    }
}

/// The unit vector `angle` radians from straight down, positive towards +x.
private func direction(_ angle: Double) -> CGVector {
    CGVector(dx: sin(angle), dy: -cos(angle))
}

private func angle(of vector: CGVector) -> Double {
    atan2(vector.dx, -vector.dy)
}

private func + (point: CGPoint, vector: CGVector) -> CGPoint {
    CGPoint(x: point.x + vector.dx, y: point.y + vector.dy)
}

private func - (point: CGPoint, vector: CGVector) -> CGPoint {
    CGPoint(x: point.x - vector.dx, y: point.y - vector.dy)
}

private func - (a: CGPoint, b: CGPoint) -> CGVector {
    CGVector(dx: a.x - b.x, dy: a.y - b.y)
}

private func + (a: CGVector, b: CGVector) -> CGVector {
    CGVector(dx: a.dx + b.dx, dy: a.dy + b.dy)
}

private func * (vector: CGVector, k: Double) -> CGVector {
    CGVector(dx: vector.dx * k, dy: vector.dy * k)
}

private extension CGVector {
    var length: Double { hypot(dx, dy) }

    func rotated(by angle: Double) -> CGVector {
        CGVector(dx: dx * cos(angle) - dy * sin(angle), dy: dx * sin(angle) + dy * cos(angle))
    }
}

// MARK: - Animation

/// What a props builder can see: the moment, the pose and where the joints ended up.
struct FigureScene {
    let time: TimeInterval
    let pose: Pose
    let skeleton: Skeleton
}

public struct FigureAnimation: Sendable {
    public let projection: FigureProjection
    /// One loop, in seconds.
    public let period: TimeInterval
    /// The most telling moment of the loop: the still shown when Reduce Motion is on.
    public let keyTime: TimeInterval
    let anchor: Double?
    let trails: [TrailJoint]
    let trailLength: TimeInterval
    let trailsInFront: Bool
    let pose: @Sendable (TimeInterval) -> Pose
    let props: @Sendable (FigureScene) -> [FigureProp]

    init(
        _ projection: FigureProjection,
        period: TimeInterval,
        keyTime: TimeInterval,
        anchor: Double? = nil,
        trails: [TrailJoint] = [],
        trailLength: TimeInterval = 0.45,
        trailsInFront: Bool = false,
        props: @escaping @Sendable (FigureScene) -> [FigureProp] = { _ in [FigureAnimations.floor()] },
        pose: @escaping @Sendable (TimeInterval) -> Pose
    ) {
        self.projection = projection
        self.period = period
        self.keyTime = keyTime
        self.anchor = anchor
        self.trails = trails
        self.trailLength = trailLength
        self.trailsInFront = trailsInFront
        self.props = props
        self.pose = pose
    }

    init(
        _ projection: FigureProjection,
        _ track: Track<Pose>,
        keyTime: TimeInterval,
        anchor: Double? = nil,
        trails: [TrailJoint] = [],
        trailLength: TimeInterval = 0.45,
        trailsInFront: Bool = false,
        props: @escaping @Sendable (FigureScene) -> [FigureProp] = { _ in [FigureAnimations.floor()] }
    ) {
        self.init(
            projection,
            period: track.period,
            keyTime: keyTime,
            anchor: anchor,
            trails: trails,
            trailLength: trailLength,
            trailsInFront: trailsInFront,
            props: props,
            pose: { track($0) }
        )
    }

    static let trailSamples = 12

    public func frame(at time: TimeInterval, withTrails: Bool = true) -> FigureFrame {
        let t = time.wrapped(period)
        let pose = self.pose(t)
        let skeleton = FigureSolver.solve(pose, projection, anchor: anchor)
        var paths: [[CGPoint]] = []
        if withTrails, !trails.isEmpty {
            let past = (1...Self.trailSamples).map { step in
                let earlier = (t - trailLength * Double(step) / Double(Self.trailSamples)).wrapped(period)
                return FigureSolver.solve(self.pose(earlier), projection, anchor: anchor)
            }
            paths = trails.map { joint in [skeleton.point(joint)] + past.map { $0.point(joint) } }
        }
        return FigureFrame(
            projection: projection,
            skeleton: skeleton,
            armDepth: Sides(left: pose.arms.left.depth, right: pose.arms.right.depth),
            legDepth: Sides(left: pose.legs.left.depth, right: pose.legs.right.depth),
            eyes: FigureSolver.eyes(pose, projection, head: skeleton.head),
            props: props(FigureScene(time: t, pose: pose, skeleton: skeleton)),
            trails: paths,
            trailsInFront: trailsInFront
        )
    }

    public var keyFrame: FigureFrame { frame(at: keyTime, withTrails: false) }
}

public enum FigureAnimations {
    public static func animation(for exerciseID: String) -> FigureAnimation? {
        library[exerciseID]
    }

    /// The figure for an exercise at `time` seconds since the animation started. Unknown ids get a friendly wave.
    public static func frame(for exerciseID: String, at time: TimeInterval) -> FigureFrame {
        (library[exerciseID] ?? fallback).frame(at: time)
    }

    public static func keyFrame(for exerciseID: String) -> FigureFrame {
        (library[exerciseID] ?? fallback).keyFrame
    }

    public static let fallback = wave

    static let library: [String: FigureAnimation] = [
        "squats": squats,
        "reach": reach,
        "shoulders": shoulders,
        "window": window,
        "neck": neck,
        "calves": calves,
        "chest": chest,
        "twists": twists,
        "pushups": pushups,
        "hips": hips,
        "march": march,
        "lunges": lunges,
        "sidebends": sideBends,
        "stepjacks": stepJacks,
        "water": water,
        "catcow": catCow,
        "backbend": backBend,
        "pelvictilt": pelvicTilt,
        "rolldown": rollDown,
        "kneehug": kneeHug,
        "hipflexor": hipFlexor,
        "hinge": hinge,
    ]

    static let ground = FigureMetrics.ground

    static func floor(from: Double = 0.16, to: Double = 0.84) -> FigureProp {
        FigureProp(.line([CGPoint(x: from, y: ground), CGPoint(x: to, y: ground)]), ink: .ground)
    }
}

// MARK: - The exercises

extension FigureAnimations {
    /// Side view, 3.2 s: sit back with the arms forward for balance, heels down.
    static let squats: FigureAnimation = {
        let stand = Pose.side.with { $0.lean = 0.04 }
        let bottom = stand.with { pose in
            pose.lean = 0.8
            pose.neck = -0.45
            pose.arms.both {
                $0.shoulder = 2.32
                $0.elbow = 0.1
            }
            pose.legs.both {
                $0.hip = 1.32
                $0.knee = 1.8
            }
        }
        let track = Track([Key(stand, hold: 0.5, move: 1.3), Key(bottom, hold: 0.3, move: 1.1)])
        return FigureAnimation(.side, track, keyTime: 1.95, anchor: 0.5, trails: [.pelvis], trailLength: 0.6)
    }()

    /// Side view, 9.4 s: up on the toes with the arms overhead, then a soft-kneed fold with the hands to the floor.
    static let reach: FigureAnimation = {
        let stand = Pose.side
        let up = stand.with { pose in
            pose.lean = -0.08
            pose.neck = -0.35
            // Slightly behind the head, so the arm does not cross the face.
            pose.arms.both {
                $0.shoulder = 3.32
                $0.elbow = 0.05
            }
            pose.legs.both { $0.foot = 0.45 }
        }
        let fold = stand.with { pose in
            pose.lean = 1.62
            pose.neck = 0.6
            pose.arms.both {
                $0.shoulder = 1.74
                $0.elbow = 0.06
            }
            pose.legs.both {
                $0.hip = 0.26
                $0.knee = 0.32
            }
        }
        let track = Track([
            Key(stand, hold: 0.6, move: 1.6),
            Key(up, hold: 1.3, move: 2.2),
            Key(fold, hold: 1.5, move: 2.2),
        ])
        return FigureAnimation(.side, track, keyTime: 2.9, anchor: 0.5, trails: [.hand(.left)], trailLength: 0.7)
    }()

    /// Front view, 8.6 s: the shoulders roll up towards the ears and down; two circles forward, two back.
    /// From the front a roll shows as a rise and fall, and the shoulders narrow as they come forward.
    static let shoulders: FigureAnimation = {
        let circles = Track([Key(0.0, hold: 0.3, move: 4.0), Key(4 * Double.pi, hold: 0.3, move: 4.0)])
        return FigureAnimation(
            .front,
            period: circles.period,
            keyTime: 1.63,
            trails: [.shoulder(.left), .shoulder(.right)],
            trailLength: 0.9,
            trailsInFront: true
        ) { t in
            // 0 is the bottom of the circle; increasing phi goes back, up, forward and down: a forward roll.
            let phi = circles(t)
            let girdle = CGVector(dx: 0.02 * sin(phi), dy: 0.027 * (1 - cos(phi)))
            return Pose.front.with { pose in
                pose.arms.both {
                    $0.girdle = girdle
                    $0.shoulder = 0.1
                    $0.elbow = 0.15
                }
            }
        }
    }()

    /// Side view, 7 s: stand at a window with a hand over the eyes and gaze at a distant point.
    static let window: FigureAnimation = {
        let pane = (x0: 0.6, x1: 0.94, y0: ground + 0.34, y1: ground + 0.86)
        let farPoint = CGPoint(x: 0.85, y: ground + 0.62)
        let stand = Pose.side.with { pose in
            pose.lean = 0.04
            pose.neck = -0.08
        }
        let look = stand.with { pose in
            pose.lean = 0.09
            pose.neck = -0.2
            pose.arms.left.reach = .head(CGVector(dx: 0.075, dy: 0.03))
            pose.arms.left.reachWeight = 1
        }
        let track = Track([Key(stand, hold: 1.0, move: 1.0), Key(look, hold: 4.0, move: 1.0)])
        let period = track.period
        let frame = [
            CGPoint(x: pane.x0, y: pane.y0), CGPoint(x: pane.x1, y: pane.y0),
            CGPoint(x: pane.x1, y: pane.y1), CGPoint(x: pane.x0, y: pane.y1),
        ]
        let midX = (pane.x0 + pane.x1) / 2
        let midY = (pane.y0 + pane.y1) / 2
        let hills = [
            CGPoint(x: pane.x0, y: pane.y0 + 0.08), CGPoint(x: 0.66, y: pane.y0 + 0.13),
            CGPoint(x: 0.72, y: pane.y0 + 0.1), CGPoint(x: 0.8, y: pane.y0 + 0.17),
            CGPoint(x: 0.88, y: pane.y0 + 0.11), CGPoint(x: pane.x1, y: pane.y0 + 0.13),
        ]
        let scenery = [
            floor(from: 0.08, to: 0.94),
            FigureProp(.loop(frame), ink: .object),
            FigureProp(.line([CGPoint(x: midX, y: pane.y0), CGPoint(x: midX, y: pane.y1)]), ink: .object),
            FigureProp(.line([CGPoint(x: pane.x0, y: midY), CGPoint(x: pane.x1, y: midY)]), ink: .object),
            FigureProp(.line([CGPoint(x: pane.x0 - 0.02, y: pane.y0), CGPoint(x: pane.x1 + 0.02, y: pane.y0)]),
                       ink: .object),
            FigureProp(.line(hills), ink: .ground),
        ]
        return FigureAnimation(
            .side,
            period: period,
            keyTime: 3.5,
            anchor: 0.34,
            props: { scene in
                let eye = FigureSolver.eyes(scene.pose, .side, head: scene.skeleton.head)[0]
                let pulse = 0.014 + 0.003 * sin(scene.time * 2 * .pi / 1.75)
                let gaze = FigureProp(
                    .line([eye, farPoint]),
                    ink: .accent,
                    opacity: 0.8 * scene.pose.arms.left.reachWeight,
                    dash: -scene.time * 0.06,
                    inFront: true
                )
                return scenery + [FigureProp(.dot(farPoint, radius: pulse), ink: .accent), gaze]
            }
        ) { t in
            // A slow scan of the horizon while looking.
            track(t).with { $0.neck += 0.05 * sin(t * 4 * .pi / period) }
        }
    }()

    /// Front view, 15 s: ear towards one shoulder, hold, back, then the other side.
    static let neck: FigureAnimation = {
        let stand = Pose.front
        let left = stand.with { pose in
            pose.neck = 0.72
            pose.arms.right.girdle = CGVector(dx: 0, dy: -0.012)
        }
        let right = stand.with { pose in
            pose.neck = -0.72
            pose.arms.left.girdle = CGVector(dx: 0, dy: -0.012)
        }
        let track = Track([
            Key(stand, hold: 1.0, move: 2.0),
            Key(left, hold: 2.5, move: 2.0),
            Key(stand, hold: 1.0, move: 2.0),
            Key(right, hold: 2.5, move: 2.0),
        ])
        return FigureAnimation(.front, track, keyTime: 4.0, trails: [.crown], trailLength: 1.2)
    }()

    /// Side view, 3 s: rise onto the toes with the arms drifting forward for balance, pause, lower the heels.
    static let calves: FigureAnimation = {
        let stand = Pose.side
        let up = stand.with { pose in
            pose.lean = 0.04
            pose.legs.both { $0.foot = 1.0 }
            pose.arms.both {
                $0.shoulder = 0.4
                $0.elbow = 0.3
            }
        }
        let track = Track([Key(stand, hold: 0.35, move: 1.1), Key(up, hold: 0.5, move: 1.05)])
        return FigureAnimation(.side, track, keyTime: 1.7, anchor: 0.5, trails: [.heel(.left)], trailLength: 0.7)
    }()

    /// Side view, 6.5 s: hands clasp behind the back and lift, chest open and chin up, then release.
    static let chest: FigureAnimation = {
        let stand = Pose.side
        let clasp = stand.with { pose in
            pose.arms.both {
                $0.shoulder = -0.45
                $0.elbow = 0.5
            }
        }
        let lift = stand.with { pose in
            pose.lean = -0.14
            pose.neck = -0.4
            pose.arms.both {
                $0.shoulder = -1.2
                $0.elbow = 0.04
            }
        }
        let track = Track([
            Key(stand, hold: 0.5, move: 1.2),
            Key(clasp, hold: 0.25, move: 1.3),
            Key(lift, hold: 1.8, move: 1.4),
        ])
        return FigureAnimation(.side, track, keyTime: 4.0, anchor: 0.5, trails: [.hand(.left)], trailLength: 0.6)
    }()

    /// Front view, 3 s: the shoulders turn about the spine; loose arms swing around the body a moment later.
    static let twists: FigureAnimation = {
        let period = 3.0
        let lag = 0.14
        return FigureAnimation(
            .front,
            period: period,
            keyTime: 0.8,
            trails: [.hand(.left), .hand(.right)],
            trailLength: 0.35
        ) { t in
            let turn = sin(2 * .pi * t / period)
            let swing = sin(2 * .pi * (t - lag) / period)
            return Pose.front.with { pose in
                pose.twist = 0.9 * turn
                pose.headYaw = 0.75 * turn
                pose.legs.both {
                    $0.hip = 0.07
                    $0.knee = 0.04
                }
                for side in FigureSide.allCases {
                    // u > 0: the arm on the side we turn to goes behind and flies out; u < 0: it wraps in front.
                    let u = side.sign * swing
                    pose.arms[side].shoulder = 0.2 + (u >= 0 ? 0.75 : 0.95) * u
                    pose.arms[side].elbow = 0.15 + (u >= 0 ? 0.25 : 0.6) * abs(u)
                    pose.arms[side].depth = -u
                }
            }
        }
    }()

    /// Side view, 2.9 s: hands on the desk edge, the straight body pivots on the toes, the elbows bend back.
    static let pushups: FigureAnimation = {
        let lean = Track([Key(0.7, hold: 0.45, move: 1.2), Key(1.0, hold: 0.2, move: 1.05)])
        let foot = 0.55
        let toeX = 0.17
        // The hands go where straight arms, perpendicular to the body, meet the desk at the top.
        let top = 0.7
        let ankle = CGPoint(x: toeX - FigureMetrics.toe * cos(foot), y: ground + FigureMetrics.toe * sin(foot))
        let shoulderReach = FigureMetrics.leg + FigureMetrics.torso - FigureMetrics.shoulderDrop
        let hand = CGPoint(
            x: ankle.x + shoulderReach * sin(top) + 0.272 * cos(top),
            y: ankle.y + shoulderReach * cos(top) - 0.272 * sin(top)
        )
        let deskTop = hand.y - 0.012
        let edge = hand.x - 0.03
        let desk = [
            floor(from: 0.04, to: 0.96),
            FigureProp(.line([CGPoint(x: edge, y: deskTop), CGPoint(x: 0.96, y: deskTop)]), ink: .object),
            FigureProp(.line([CGPoint(x: edge + 0.03, y: deskTop), CGPoint(x: edge + 0.03, y: ground)]), ink: .object),
            FigureProp(.line([CGPoint(x: 0.92, y: deskTop), CGPoint(x: 0.92, y: ground)]), ink: .object),
        ]
        return FigureAnimation(.side, period: lean.period, keyTime: 1.75, anchor: toeX, props: { _ in desk }) { t in
            let angle = lean(t)
            return Pose.side.with { pose in
                pose.lean = angle
                pose.neck = -0.18
                pose.legs.both {
                    $0.hip = -angle
                    $0.knee = 0
                    $0.foot = foot
                }
                pose.arms.both {
                    $0.reach = .world(hand)
                    $0.reachWeight = 1
                }
            }
        }
    }()

    /// Front view, 6.8 s: hands on the hips, the pelvis circles one way, then the other. A dot runs round an
    /// orbit drawn at hip height, passing behind the body on the far half, so the circle reads in a flat view.
    static let hips: FigureAnimation = {
        let circle = Track([Key(0.0, hold: 0.2, move: 3.2), Key(2 * Double.pi, hold: 0.2, move: 3.2)])
        let feet = Sides(left: CGPoint(x: 0.555, y: ground), right: CGPoint(x: 0.445, y: ground))
        let orbit = Orbit(
            center: CGPoint(x: 0.5, y: standingHeight(x: 0.5, plants: feet)),
            radius: (x: 0.12, y: 0.03)
        )
        return FigureAnimation(
            .front,
            period: circle.period,
            keyTime: 1.0,
            props: { scene in
                // The far half of the orbit is behind the body.
                [floor()] + orbit.marker(at: scene.time, angle: { circle($0) }, inFront: { sin($0) <= 0 })
            }
        ) { t in
            let phi = circle(t)
            let x = 0.5 + 0.03 * cos(phi)
            let tilt = 0.1 * cos(phi)
            return Pose.front.with { pose in
                pose.prop = phi
                pose.root = CGPoint(x: x, y: standingHeight(x: x, tilt: tilt, plants: feet))
                pose.pelvisTilt = tilt
                // The shoulders stay over the feet and the head stays level.
                pose.lean = -0.16 * cos(phi)
                pose.neck = 0.12 * cos(phi)
                pose.arms.both {
                    $0.reach = .hip(CGVector(dx: 0.03, dy: 0.025))
                    $0.reachWeight = 1
                }
                for side in FigureSide.allCases {
                    pose.legs[side].plant = feet[side]
                    pose.legs[side].plantWeight = 1
                }
            }
        }
    }()

    /// Side view, 1.2 s: knees high, the opposite arm swings forward.
    static let march: FigureAnimation = {
        let down = Pose.side.with { pose in
            pose.arms.both {
                $0.shoulder = 0.15
                $0.elbow = 0.6
            }
            pose.legs.both { $0.knee = 0.1 }
        }
        func lift(_ side: FigureSide) -> Pose {
            let other: FigureSide = side == .left ? .right : .left
            return down.with { pose in
                pose.lean = 0.03
                pose.legs[side] = Leg(hip: 1.35, knee: 1.45, foot: 0.4, depth: pose.legs[side].depth)
                pose.legs[other] = Leg(depth: pose.legs[other].depth)
                pose.arms[other].shoulder = 0.85
                pose.arms[other].elbow = 1.0
                pose.arms[side].shoulder = -0.5
                pose.arms[side].elbow = 0.5
            }
        }
        let track = Track([
            Key(lift(.left), hold: 0.06, move: 0.27),
            Key(down, move: 0.27),
            Key(lift(.right), hold: 0.06, move: 0.27),
            Key(down, move: 0.27),
        ])
        return FigureAnimation(.side, track, keyTime: 0.03, trails: [.knee(.left), .knee(.right)], trailLength: 0.3)
    }()

    /// Side view, 7.2 s: step forward, lower the back knee towards the floor, rise, step back; then the other leg.
    static let lunges: FigureAnimation = {
        let step = Track([Key(0.0, hold: 0.3, move: 0.7), Key(1.0, hold: 1.9, move: 0.7)])
        let depth = Track([
            Key(0.0, hold: 1.0, move: 0.8),
            Key(1.0, hold: 0.3, move: 0.8),
            Key(0.0, hold: 0.7, move: 0),
        ])
        let half = step.period
        let home = 0.3
        return FigureAnimation(
            .side,
            period: 2 * half,
            keyTime: 1.95,
            trails: [.knee(.left), .knee(.right)],
            trailLength: 0.5
        ) { t in
            let first = t < half
            let local = first ? t : t - half
            let s = step(local)
            let d = depth(local)
            let forward: FigureSide = first ? .left : .right
            let back: FigureSide = first ? .right : .left
            return Pose.side.with { pose in
                // The pelvis travels with the step so the front foot is in reach when it lands, then sinks.
                pose.root = CGPoint(x: home + 0.19 * s + 0.05 * d, y: ground + 0.345 - 0.08 * s - 0.065 * d)
                pose.lean = 0.04 + 0.04 * s
                pose.neck = -0.05
                pose.legs[forward].plant = CGPoint(x: home + 0.41 * s, y: ground + 0.045 * sin(.pi * s))
                pose.legs[forward].plantWeight = 1
                pose.legs[forward].foot = -0.15 * sin(.pi * s)
                // The back foot rolls onto its toes; the toes stay where they are.
                let roll = d + 0.15 * s
                let toe = home + FigureMetrics.toe
                pose.legs[back].foot = roll
                pose.legs[back].plant = CGPoint(
                    x: toe - FigureMetrics.toe * cos(roll),
                    y: ground + FigureMetrics.toe * sin(roll)
                )
                pose.legs[back].plantWeight = 1
                pose.arms[forward].shoulder = 0.06 - 0.25 * s
                pose.arms[back].shoulder = 0.06 + 0.25 * s
            }
        }
    }()

    /// Front view, 6.6 s: one hand slides down the thigh while the other arm arcs overhead; then the other side.
    static let sideBends: FigureAnimation = {
        let feet = Sides(left: CGPoint(x: 0.585, y: ground), right: CGPoint(x: 0.415, y: ground))
        let stand = Pose.front.with { pose in
            pose.arms.both {
                $0.reach = .thigh(0.3, CGVector(dx: 0.026, dy: 0))
                $0.reachWeight = 1
            }
            for side in FigureSide.allCases {
                pose.legs[side].plant = feet[side]
                pose.legs[side].plantWeight = 1
            }
        }
        func bend(towards side: FigureSide) -> Pose {
            let other: FigureSide = side == .left ? .right : .left
            return stand.with { pose in
                pose.root.x = 0.5 - side.sign * 0.025
                pose.lean = side.sign * 0.62
                pose.neck = side.sign * 0.12
                pose.arms[side].reach = .thigh(0.62, CGVector(dx: 0.026, dy: 0))
                pose.arms[other].reachWeight = 0
                pose.arms[other].shoulder = 3.3
                pose.arms[other].elbow = -0.5
            }
        }
        let track = Track([
            Key(stand, hold: 0.3, move: 1.3),
            Key(bend(towards: .left), hold: 0.5, move: 1.2),
            Key(stand, hold: 0.3, move: 1.3),
            Key(bend(towards: .right), hold: 0.5, move: 1.2),
        ])
        return FigureAnimation(.front, period: track.period, keyTime: 1.8, trails: [.hand(.left), .hand(.right)],
                               trailLength: 0.6) { t in
            track(t).with { $0.root.y = standingHeight(x: $0.root.x, plants: feet) }
        }
    }()

    /// Front view, 3 s: step out to one side with the arms sweeping overhead, step back; then the other side.
    static let stepJacks: FigureAnimation = {
        let step = Track([
            Key(0.0, hold: 0.1, move: 0.55),
            Key(1.0, hold: 0.2, move: 0.55),
            Key(0.0, hold: 0.1, move: 0),
        ])
        let half = step.period
        return FigureAnimation(
            .front,
            period: 2 * half,
            keyTime: 0.75,
            trails: [.hand(.left), .hand(.right)],
            trailLength: 0.35
        ) { t in
            let first = t < half
            let s = step(first ? t : t - half)
            let mover: FigureSide = first ? .right : .left
            var feet = Sides(CGPoint.zero)
            for side in FigureSide.allCases {
                let moving = side == mover
                let x = 0.5 + side.sign * (0.032 + (moving ? 0.15 * s : 0))
                // A low lift: in the front view any lift bends the knee sideways.
                feet[side] = CGPoint(x: x, y: ground + (moving ? 0.012 * sin(.pi * s) : 0))
            }
            return Pose.front.with { pose in
                let x = 0.5 + mover.sign * 0.05 * s
                pose.root = CGPoint(x: x, y: standingHeight(x: x, plants: feet))
                // The arms straighten as they sweep through the sides up into a V.
                pose.arms.both {
                    $0.shoulder = 0.14 + 2.62 * s
                    $0.elbow = 0.12 * (1 - s)
                }
                for side in FigureSide.allCases {
                    pose.legs[side].plant = feet[side]
                    pose.legs[side].plantWeight = 1
                }
            }
        }
    }()

    /// Side view, 5.8 s: lift the glass, tip the head back and drink, lower it. The water surface stays level.
    static let water: FigureAnimation = {
        let hold = Pose.side.with { pose in
            pose.arms.left.shoulder = 0.3
            pose.arms.left.elbow = 1.25
        }
        let sip = hold.with { pose in
            pose.neck = -0.1
            pose.prop = 0.35
            pose.arms.left.reach = .head(CGVector(dx: 0.105, dy: -0.045))
            pose.arms.left.reachWeight = 1
        }
        let drink = sip.with { pose in
            pose.lean = -0.06
            pose.neck = -0.45
            pose.prop = 1.25
        }
        let track = Track([
            Key(hold, hold: 0.8, move: 1.1),
            Key(sip, hold: 0.1, move: 0.6),
            Key(drink, hold: 1.6, move: 0.6),
            Key(sip, move: 1.0),
        ])
        // Full while lifted, drunk while tipped, and quietly refilled while the glass rests at the waist.
        let level = Track([
            Key(0.3, move: 0.8),
            Key(0.78, hold: 1.8, move: 1.6, .linear),
            Key(0.3, hold: 1.6, move: 0),
        ])
        return FigureAnimation(
            .side,
            period: track.period,
            keyTime: 3.4,
            anchor: 0.5,
            props: { scene in
                [floor()] + glass(at: scene.skeleton.hands.left, tilt: scene.pose.prop, level: level(scene.time))
            }
        ) { track($0) }
    }()

    // MARK: Spine and lower back

    /// Side view, 7 s: soft knees, hands on the thighs, back hinged forward. The spine rounds up like a cat (pelvis
    /// tucked, head down), then sags into a cow (pelvis tipped out, chest forward, head up).
    static let catCow: FigureAnimation = {
        let base = Pose.side.with { pose in
            pose.legs.both {
                $0.hip = 0.35
                $0.knee = 0.55
            }
            pose.arms.both {
                $0.reach = .thigh(0.75, CGVector(dx: 0.01, dy: 0.02))
                $0.reachWeight = 1
            }
        }
        let cat = base.with { pose in
            pose.lean = 0.4
            pose.spine = Spine(lower: 0.5, upper: 0.45)
            pose.neck = 0.75
            pose.arms.both { $0.girdle = CGVector(dx: 0.01, dy: 0.008) }
        }
        let cow = base.with { pose in
            pose.lean = 1.35
            pose.spine = Spine(lower: -0.25, upper: -0.3)
            pose.neck = -0.75
            pose.arms.both { $0.girdle = CGVector(dx: -0.01, dy: 0) }
        }
        let track = Track([Key(cat, hold: 1.1, move: 2.4), Key(cow, hold: 1.1, move: 2.4)])
        return FigureAnimation(.side, track, keyTime: 0.5, anchor: 0.5, props: { [floor(), pelvisBowl($0)] })
    }()

    /// Side view, 5.6 s: palms on the lower back, the hips go forward and the body leans back with the head
    /// following; then upright again.
    static let backBend: FigureAnimation = {
        let stand = Pose.side.with { pose in
            pose.arms.both {
                $0.reach = .back(CGVector(dx: -0.035, dy: -0.01))
                $0.reachWeight = 1
            }
        }
        let bend = stand.with { pose in
            pose.lean = -0.2
            pose.spine = Spine(lower: -0.25, upper: -0.2)
            pose.neck = -0.35
            pose.legs.both {
                $0.hip = -0.12
                $0.knee = 0.15
            }
        }
        let track = Track([Key(stand, hold: 1.1, move: 1.7), Key(bend, hold: 1.1, move: 1.7)])
        return FigureAnimation(.side, track, keyTime: 3.4, anchor: 0.5, trails: [.head], trailLength: 0.8)
    }()

    /// Side view, 4 s: soft knees, hands on the hips. The pelvis tips forward (the lower back arches) and back (it
    /// flattens) while the chest stays upright. The motion is small, so the pelvis is drawn as a tilting bowl.
    static let pelvicTilt: FigureAnimation = {
        let base = Pose.side.with { pose in
            pose.legs.both {
                $0.hip = 0.12
                $0.knee = 0.25
            }
            pose.arms.both {
                $0.reach = .hip(CGVector(dx: 0, dy: 0.035))
                $0.reachWeight = 1
            }
        }
        let forward = base.with { pose in
            pose.lean = 0.3
            pose.spine = Spine(lower: -0.22, upper: -0.08)
            pose.legs.both { $0.hip = 0.16 }
        }
        let back = base.with { pose in
            pose.lean = -0.22
            pose.spine = Spine(lower: 0.14, upper: 0.08)
            pose.legs.both {
                $0.hip = 0.06
                $0.knee = 0.3
            }
        }
        let track = Track([Key(forward, hold: 0.5, move: 1.5), Key(back, hold: 0.5, move: 1.5)])
        return FigureAnimation(.side, track, keyTime: 0.25, anchor: 0.5, props: { [floor(), pelvisBowl($0)] })
    }()

    /// Side view, 10 s: the head drops, then the spine rolls down one segment at a time until the hands hang near
    /// the floor; it rolls back up from the bottom, and the head comes up last.
    static let rollDown: FigureAnimation = {
        /// The arms hang straight down, whatever the spine does.
        func hanging(_ pose: Pose) -> Pose {
            pose.with { pose in
                let chest = pose.chest
                pose.arms.both {
                    $0.shoulder = chest
                    $0.elbow = 0.08
                }
            }
        }
        let tall = hanging(Pose.side)
        let head = hanging(tall.with { $0.neck = 0.65 })
        let upper = hanging(head.with { $0.spine.upper = 0.5 })
        let lower = hanging(upper.with { $0.spine.lower = 0.5 })
        let bottom = hanging(lower.with { pose in
            pose.lean = 0.95
            pose.legs.both {
                $0.hip = 0.22
                $0.knee = 0.38
            }
        })
        // Back up from the bottom: hips and lumbar spine first, the head last.
        let hipsUp = hanging(bottom.with { pose in
            pose.lean = 0
            pose.legs = tall.legs
        })
        let lowerUp = hanging(hipsUp.with { $0.spine.lower = 0 })
        let upperUp = hanging(lowerUp.with { $0.spine.upper = 0 })
        let track = Track([
            Key(tall, hold: 1.0, move: 0.9, .in),
            Key(head, move: 0.9, .linear),
            Key(upper, move: 0.9, .linear),
            Key(lower, move: 1.2, .out),
            Key(bottom, hold: 1.2, move: 1.2, .in),
            Key(hipsUp, move: 0.9, .linear),
            Key(lowerUp, move: 0.9, .linear),
            Key(upperUp, move: 0.9, .out),
        ])
        return FigureAnimation(.side, track, keyTime: 5.4, anchor: 0.5, trails: [.head], trailLength: 0.9)
    }()

    /// Side view, 8.2 s: on one leg, both hands pull the other knee to the chest and hold; then the other leg.
    static let kneeHug: FigureAnimation = {
        let stand = Pose.side.with { $0.root.x = 0.44 }
        func hug(_ side: FigureSide) -> Pose {
            stand.with { pose in
                pose.lean = 0.12
                pose.spine = Spine(lower: 0.06, upper: 0.12)
                pose.neck = 0.15
                pose.legs[side].hip = 2.5
                pose.legs[side].knee = 2.5
                pose.legs[side].foot = 0.6
                pose.arms.both {
                    $0.reach = .knee(side, CGVector(dx: 0.02, dy: -0.035))
                    $0.reachWeight = 1
                }
            }
        }
        let track = Track([
            Key(stand, hold: 0.5, move: 1.0),
            Key(hug(.left), hold: 1.6, move: 1.0),
            Key(stand, hold: 0.5, move: 1.0),
            Key(hug(.right), hold: 1.6, move: 1.0),
        ])
        // The standing leg keeps its angles, so with the pelvis held in place its foot stays put.
        return FigureAnimation(.side, track, keyTime: 2.0, trails: [.knee(.left), .knee(.right)], trailLength: 0.5)
    }()

    /// Side view, 10 s: step back into a long split stance, back heel up. Tuck the pelvis and pulse the back hip
    /// forward twice, step together, switch legs.
    static let hipFlexor: FigureAnimation = {
        let step = Track([
            Key(0.0, hold: 0.3, move: 1.0),
            Key(1.0, hold: 2.4, move: 1.0),
            Key(0.0, hold: 0.3, move: 0),
        ])
        let pulse = Track([
            Key(0.0, hold: 1.3, move: 0.6),
            Key(1.0, move: 0.6),
            Key(0.0, move: 0.6),
            Key(1.0, move: 0.6),
            Key(0.0, hold: 1.3, move: 0),
        ])
        let half = step.period
        let home = 0.52
        return FigureAnimation(
            .side,
            period: 2 * half,
            keyTime: 1.9,
            trails: [.pelvis],
            trailLength: 0.6,
            props: { [floor(), pelvisBowl($0)] }
        ) { t in
            let first = t < half
            let local = first ? t : t - half
            let s = step(local)
            let p = pulse(local)
            // The near leg steps back first, so the stretched hip is the one drawn in front.
            let back: FigureSide = first ? .left : .right
            let front: FigureSide = first ? .right : .left
            return Pose.side.with { pose in
                pose.root = CGPoint(x: home - 0.17 * s + 0.025 * p, y: ground + 0.345 - 0.065 * s - 0.015 * p)
                // The pelvis tucks under while the chest stays upright.
                pose.lean = -0.15 * s - 0.06 * p
                pose.spine = Spine(lower: 0.1 * s, upper: 0.05 * s + 0.06 * p)
                pose.legs[front].plant = CGPoint(x: home, y: ground)
                pose.legs[front].plantWeight = 1
                let toe = home + FigureMetrics.toe - 0.43 * s
                pose.legs[back].foot = s
                pose.legs[back].plant = CGPoint(
                    x: toe - FigureMetrics.toe * cos(s),
                    y: ground + FigureMetrics.toe * sin(s) + 0.035 * sin(.pi * s)
                )
                pose.legs[back].plantWeight = 1
                pose.arms.both {
                    $0.reach = .hip(CGVector(dx: 0, dy: 0.035))
                    $0.reachWeight = 1
                }
            }
        }
    }()

    /// Side view, 3.8 s: hands on the hips, the hips push back and a flat back pivots forward with the knees barely
    /// bent; then stand tall. A stick laid along the back shows that it stays straight, unlike in a squat.
    static let hinge: FigureAnimation = {
        let stand = Pose.side.with { pose in
            pose.arms.both {
                $0.reach = .hip(CGVector(dx: 0, dy: 0.035))
                $0.reachWeight = 1
            }
        }
        let bent = stand.with { pose in
            pose.lean = 0.98
            pose.neck = -0.08
            pose.legs.both {
                $0.hip = 0.3
                $0.knee = 0.38
            }
        }
        let track = Track([Key(stand, hold: 0.6, move: 1.5), Key(bent, hold: 0.4, move: 1.3)])
        return FigureAnimation(
            .side,
            track,
            keyTime: 2.3,
            anchor: 0.5,
            trails: [.pelvis],
            trailLength: 0.6,
            props: { scene in [floor(), dowel(along: scene)] }
        )
    }()

    /// The pelvis as a small bowl that tilts with it: tipped forward, its front drops; tucked under, its back drops.
    /// The usual cue for pelvic tilts, and the only way to see them on a stick figure.
    static func pelvisBowl(_ scene: FigureScene) -> FigureProp {
        let lean = scene.pose.lean
        let across = CGVector(dx: cos(lean), dy: -sin(lean))
        let up = CGVector(dx: sin(lean), dy: cos(lean))
        let center = scene.skeleton.pelvis + up * 0.01
        let outline = (0..<24).map { i -> CGPoint in
            let a = Double(i) / 24 * 2 * .pi
            return center + across * (0.05 * cos(a)) + up * (0.017 * sin(a))
        }
        return FigureProp(.area(outline), ink: .accent, opacity: 0.85, inFront: true)
    }

    /// A straight stick resting on a flat back, from below the pelvis to above the head.
    static func dowel(along scene: FigureScene) -> FigureProp {
        let lean = scene.pose.lean
        let up = CGVector(dx: sin(lean), dy: cos(lean))
        let behind = CGVector(dx: -cos(lean), dy: sin(lean)) * 0.04
        let start = scene.skeleton.pelvis + behind - up * 0.05
        let end = scene.skeleton.neckBase + behind + up * 0.15
        return FigureProp(.line([start, end]), ink: .accent, opacity: 0.6)
    }

    /// The fallback for an unknown exercise: a friendly wave.
    static let wave: FigureAnimation = {
        let up = Pose.front.with { pose in
            pose.neck = -0.1
            pose.arms.right.shoulder = 2.4
            pose.arms.right.elbow = -0.55
        }
        let wag = up.with { $0.arms.right.elbow = 0.1 }
        let track = Track([Key(up, hold: 0.05, move: 0.4), Key(wag, hold: 0.05, move: 0.4)])
        return FigureAnimation(.front, track, keyTime: 0, trails: [.hand(.right)], trailLength: 0.25)
    }()

    /// A dashed ellipse with a dot that moves along it and a fading tail behind the dot: shows a motion that the
    /// flat figure alone cannot, such as a circle around the hips.
    struct Orbit: Sendable {
        let center: CGPoint
        let radius: (x: Double, y: Double)

        func point(_ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius.x * cos(angle), y: center.y + radius.y * sin(angle))
        }

        /// `angle` gives the dot's angle at any time; `inFront` says which angles pass in front of the body.
        func marker(
            at time: TimeInterval,
            angle: (TimeInterval) -> Double,
            inFront: (Double) -> Bool
        ) -> [FigureProp] {
            let path = (0..<48).map { point(Double($0) / 48 * 2 * .pi) }
            let tail = (0...8).map { point(angle(time - 0.06 * Double($0))) }
            let arcs = (0..<8).map { i in
                let middle = angle(time - 0.06 * (Double(i) + 0.5))
                return FigureProp(.line([tail[i], tail[i + 1]]), ink: .accent, opacity: 0.8 * (1 - Double(i) / 8),
                                  inFront: inFront(middle))
            }
            let now = angle(time)
            return [FigureProp(.loop(path), ink: .accent, opacity: 0.25, dash: 0)] + arcs + [
                FigureProp(.dot(point(now), radius: 0.017), ink: .accent, inFront: inFront(now)),
            ]
        }
    }

    /// The highest pelvis from which both legs reach their ankle targets, so the knees are only just soft.
    /// Front view; legs with more slack than this would bow outwards.
    static func standingHeight(x: Double, tilt: Double = 0, plants: Sides<CGPoint>) -> Double {
        let reach = FigureMetrics.leg - 0.0006
        let heights = FigureSide.allCases.map { side in
            let hip = CGVector(
                dx: side.sign * FigureMetrics.hipHalfWidth * cos(tilt),
                dy: side.sign * FigureMetrics.hipHalfWidth * sin(tilt)
            )
            let dx = plants[side].x - (x + hip.dx)
            return plants[side].y + max(0, reach * reach - dx * dx).squareRoot() - hip.dy
        }
        return heights.min() ?? 0
    }

    /// A glass held at its lower part. `tilt` > 0 turns the rim towards the face; `level` is the height of the
    /// water as a fraction of the glass, measured along its axis.
    static func glass(at hand: CGPoint, tilt: Double, level: Double) -> [FigureProp] {
        let axis = CGVector(dx: -sin(tilt), dy: cos(tilt))
        let across = CGVector(dx: cos(tilt), dy: sin(tilt))
        let height = 0.1
        let base = hand - axis * 0.035
        let rim = base + axis * height
        let corners = [base - across * 0.022, base + across * 0.022, rim + across * 0.029, rim - across * 0.029]
        let surface = (base + axis * (height * level)).y
        return [
            FigureProp(.area(clip(corners, below: surface)), ink: .object, inFront: true),
            FigureProp(.loop(corners), ink: .body, inFront: true),
        ]
    }

    /// The part of a convex polygon below the horizontal line y = `level`.
    static func clip(_ polygon: [CGPoint], below level: Double) -> [CGPoint] {
        var result: [CGPoint] = []
        for (index, a) in polygon.enumerated() {
            let b = polygon[(index + 1) % polygon.count]
            if a.y <= level { result.append(a) }
            if (a.y < level) != (b.y < level) {
                let t = (level - a.y) / (b.y - a.y)
                result.append(.blend(a, b, t))
            }
        }
        return result
    }
}
