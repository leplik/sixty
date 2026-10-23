import CoreGraphics
import Foundation
import Testing
@testable import SixtyCore

/// Every exercise plus the fallback, which an unknown id gets.
private let figureNames = Exercises.all.map(\.id) + ["fallback"]
/// Exercises in which a foot leaves the floor on purpose. None of them hops: one foot always stays down.
private let steppingNames: Set = ["march", "lunges", "stepjacks", "kneehug", "hipflexor"]

private func animation(_ name: String) -> FigureAnimation {
    FigureAnimations.animation(for: name) ?? FigureAnimations.fallback
}

/// Evenly spread moments across one loop.
private func moments(_ animation: FigureAnimation, count: Int = 240) -> [TimeInterval] {
    (0..<count).map { animation.period * Double($0) / Double(count) }
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    hypot(a.x - b.x, a.y - b.y)
}

/// The z component of (b - origin) × (c - origin).
private func cross(_ origin: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
    (b.x - origin.x) * (c.y - origin.y) - (b.y - origin.y) * (c.x - origin.x)
}

/// The inner angle at `joint`, in degrees: 180 is a straight limb.
private func innerAngle(_ a: CGPoint, _ joint: CGPoint, _ b: CGPoint) -> Double {
    let first = atan2(a.y - joint.y, a.x - joint.x)
    let second = atan2(b.y - joint.y, b.x - joint.x)
    let turn = abs(remainder(first - second, 2 * .pi))
    return turn * 180 / .pi
}

private func largestMove(_ from: [CGPoint], _ to: [CGPoint]) -> Double {
    zip(from, to).map(distance).max() ?? 0
}

@Suite("Figure")
struct FigureTests {
    @Test func everyExerciseHasItsOwnAnimation() {
        #expect(Set(FigureAnimations.library.keys) == Set(Exercises.all.map(\.id)))
        let wave = FigureAnimations.fallback
        for exercise in Exercises.all {
            guard let own = FigureAnimations.animation(for: exercise.id) else {
                Issue.record("\(exercise.id) has no animation")
                continue
            }
            #expect(own.keyFrame.skeleton != wave.keyFrame.skeleton, "\(exercise.id) looks like the fallback")
        }
    }

    @Test func unknownIDsGetTheFallback() {
        #expect(FigureAnimations.animation(for: "no-such-exercise") == nil)
        #expect(FigureAnimations.frame(for: "no-such-exercise", at: 0.3) == FigureAnimations.fallback.frame(at: 0.3))
        #expect(FigureAnimations.keyFrame(for: "") == FigureAnimations.fallback.keyFrame)
    }

    @Test(arguments: figureNames)
    func bonesKeepTheirLength(_ name: String) {
        let animation = animation(name)
        let foot = animation.projection == .side ? FigureMetrics.heel + FigureMetrics.toe : FigureMetrics.frontToe
        var error = 0.0
        for time in moments(animation) {
            let s = animation.frame(at: time, withTrails: false).skeleton
            var lengths = [
                distance(s.pelvis, s.lowerBack) - FigureMetrics.spineSegment,
                distance(s.lowerBack, s.upperBack) - FigureMetrics.spineSegment,
                distance(s.upperBack, s.neckBase) - FigureMetrics.spineSegment,
                distance(s.neckBase, s.head) - FigureMetrics.neck,
                distance(s.head, s.crown) - FigureMetrics.headRadius,
            ]
            for side in FigureSide.allCases {
                lengths += [
                    distance(s.shoulders[side], s.elbows[side]) - FigureMetrics.upperArm,
                    distance(s.elbows[side], s.hands[side]) - FigureMetrics.forearm,
                    distance(s.hips[side], s.knees[side]) - FigureMetrics.thigh,
                    distance(s.knees[side], s.ankles[side]) - FigureMetrics.shin,
                    distance(s.heels[side], s.toes[side]) - foot,
                ]
                // The shoulder and hip bars are projections: twists and shrugs may shorten them, never stretch them.
                #expect(distance(s.pelvis, s.hips[side]) <= FigureMetrics.hipHalfWidth + 1e-9)
                #expect(distance(s.neckBase, s.shoulders[side]) <= FigureMetrics.shoulderHalfWidth + 0.06)
            }
            error = max(error, lengths.map(abs).max() ?? 0)
        }
        #expect(error < 1e-9, "\(name): a bone changes length by \(error)")
    }

    @Test(arguments: figureNames)
    func staysInsideTheBox(_ name: String) {
        let animation = animation(name)
        let r = FigureMetrics.headRadius
        for time in moments(animation) {
            let frame = animation.frame(at: time)
            let head = frame.skeleton.head
            let headBounds = [CGPoint(x: head.x - r, y: head.y - r), CGPoint(x: head.x + r, y: head.y + r)]
            let points = frame.skeleton.points + frame.eyes + frame.props.flatMap(\.points)
                + frame.trails.flatMap { $0 } + headBounds
            let outside = points.filter { !(0.01...0.99).contains($0.x) || !(0.01...0.99).contains($0.y) }
            #expect(outside.isEmpty, "\(name) at \(time) s: \(outside)")
        }
    }

    @Test(arguments: figureNames)
    func loopsSeamlessly(_ name: String) {
        let animation = animation(name)
        #expect(animation.period > 0.5)
        #expect((0..<animation.period).contains(animation.keyTime))
        for time in moments(animation, count: 60) {
            let now = animation.frame(at: time).skeleton.points
            let later = animation.frame(at: time + animation.period).skeleton.points
            let earlier = animation.frame(at: time - 3 * animation.period).skeleton.points
            #expect(largestMove(now, later) < 1e-9, "\(name) differs one loop later at \(time) s")
            #expect(largestMove(now, earlier) < 1e-9, "\(name) differs three loops earlier at \(time) s")
        }
    }

    /// Sampled at 120 fps across the whole loop and its wrap-around: nothing teleports.
    @Test(arguments: figureNames)
    func movesWithoutJumps(_ name: String) {
        let animation = animation(name)
        let step = 1.0 / 120
        var previous = animation.frame(at: -step, withTrails: false).skeleton.points
        var worst = (move: 0.0, time: 0.0)
        for index in 0...Int(animation.period / step) + 1 {
            let time = Double(index) * step
            let points = animation.frame(at: time, withTrails: false).skeleton.points
            let move = largestMove(previous, points)
            if move > worst.move { worst = (move, time) }
            previous = points
        }
        #expect(worst.move < 0.02, "\(name) jumps by \(worst.move) at \(worst.time) s")
    }

    @Test(arguments: figureNames)
    func standsOnTheFloor(_ name: String) {
        let animation = animation(name)
        let ground = FigureMetrics.ground
        for time in moments(animation) {
            let s = animation.frame(at: time, withTrails: false).skeleton
            let contacts = [s.heels.left, s.heels.right, s.toes.left, s.toes.right].map(\.y)
            #expect(abs((contacts.min() ?? 0) - ground) < 1e-9, "\(name) floats at \(time) s")
            let below = s.points.filter { $0.y < ground - 1e-9 }
            #expect(below.isEmpty, "\(name) goes through the floor at \(time) s")
            #expect(s.head.y - FigureMetrics.headRadius > ground, "\(name): head on the floor at \(time) s")
            if !steppingNames.contains(name) {
                for side in FigureSide.allCases {
                    let lowest = min(s.heels[side].y, s.toes[side].y)
                    #expect(lowest - ground < 1e-3, "\(name): the \(side) foot lifts at \(time) s")
                }
            }
        }
    }

    @Test(arguments: figureNames)
    func jointsBendTheRightWay(_ name: String) {
        let animation = animation(name)
        let front = animation.projection == .front
        for time in moments(animation) {
            let s = animation.frame(at: time, withTrails: false).skeleton
            // The spine curls smoothly, never kinks; the head never folds onto the chest or the back.
            let spine = [s.pelvis, s.lowerBack, s.upperBack, s.neckBase, s.head]
            for i in 1..<(spine.count - 1) {
                let kink = 180 - innerAngle(spine[i - 1], spine[i], spine[i + 1])
                #expect(kink < (i == 3 ? 55 : 40), "\(name): the spine kinks by \(kink)° at joint \(i), \(time) s")
            }
            for side in FigureSide.allCases {
                let mirror = front ? side.sign : 1
                // Knees point forward (side view) or outward (front view), never backward or inward.
                let knee = cross(s.hips[side], s.ankles[side], s.knees[side])
                #expect(mirror * knee >= -1e-9, "\(name): the \(side) knee bends backward at \(time) s")
                // In the side view the forearm folds forward: an elbow never bends backward.
                if !front {
                    let elbow = cross(s.shoulders[side], s.hands[side], s.elbows[side])
                    #expect(elbow <= 1e-9, "\(name): the \(side) elbow bends backward at \(time) s")
                }
                // And no joint folds tighter than a person can.
                let kneeAngle = innerAngle(s.hips[side], s.knees[side], s.ankles[side])
                let elbowAngle = innerAngle(s.shoulders[side], s.elbows[side], s.hands[side])
                #expect(kneeAngle > 25, "\(name): the \(side) knee folds to \(kneeAngle)° at \(time) s")
                #expect(elbowAngle > 25, "\(name): the \(side) elbow folds to \(elbowAngle)° at \(time) s")
            }
        }
    }

    @Test(arguments: figureNames)
    func actuallyMoves(_ name: String) {
        let animation = animation(name)
        let start = animation.frame(at: 0, withTrails: false).skeleton.points
        let farthest = moments(animation)
            .map { largestMove(start, animation.frame(at: $0, withTrails: false).skeleton.points) }
            .max() ?? 0
        #expect(farthest > 0.04, "\(name) hardly moves: \(farthest)")
    }

    @Test func trailsStartAtTheJointAndFollowItsPath() {
        let squats = FigureAnimations.squats
        let frame = squats.frame(at: 1.2)
        #expect(frame.trails.count == 1)
        #expect(frame.trails[0].count == FigureAnimation.trailSamples + 1)
        #expect(distance(frame.trails[0][0], frame.skeleton.pelvis) < 1e-12)
        let earlier = squats.frame(at: 1.2 - squats.trailLength, withTrails: false).skeleton.pelvis
        #expect(distance(frame.trails[0].last ?? .zero, earlier) < 1e-9)
    }

    @Test func tracksHoldThenEase() {
        let track = Track([Key(0.0, hold: 1, move: 2), Key(10.0, hold: 1, move: 2, .linear)])
        #expect(track.period == 6)
        #expect(track(0.5) == 0)
        #expect(abs(track(2) - 5) < 1e-12)
        #expect(track(3.5) == 10)
        #expect(abs(track(5) - 5) < 1e-12)
        #expect(abs(track(-1) - track(5)) < 1e-12)
    }
}
