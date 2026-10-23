import Foundation

/// One thing to do during half of a break. `title` and `detail` are English localisation keys.
public struct Exercise: Equatable, Sendable, Identifiable {
    public enum Focus: Sendable {
        /// Moves the spine and the lower back: the parts that sitting hurts most.
        case spine
        /// Legs, shoulders, neck, eyes, circulation.
        case general
    }

    public let id: String
    public let title: String
    public let detail: String
    public let focus: Focus

    public init(id: String, title: String, detail: String, focus: Focus = .general) {
        self.id = id
        self.title = title
        self.detail = detail
        self.focus = focus
    }
}

/// What one break shows: one spine exercise, then one other, each for half of the break.
public struct BreakPlan: Equatable, Sendable {
    public let exercises: [Exercise]
    public let duration: TimeInterval

    public init(exercises: [Exercise], duration: TimeInterval) {
        precondition(!exercises.isEmpty)
        self.exercises = exercises
        self.duration = duration
    }

    public var segment: TimeInterval { duration / Double(exercises.count) }

    /// The exercise shown `elapsed` seconds into the break.
    public func index(at elapsed: TimeInterval) -> Int {
        min(exercises.count - 1, max(0, Int(elapsed / segment)))
    }

    /// Seconds left for the exercise shown at `elapsed`.
    public func secondsLeftInSegment(at elapsed: TimeInterval) -> TimeInterval {
        max(0, segment * Double(index(at: elapsed) + 1) - max(0, elapsed))
    }
}

public enum Exercises {
    /// Every exercise is done standing: the point of a break is to get off the chair.
    /// Each `detail` starts with "Stand" (a unit test checks it). No equipment; each fits in 30 seconds.
    public static let all: [Exercise] = [
        // Spine and lower back: move every segment and get blood into the lumbar area after sitting.
        Exercise(id: "catcow", title: "Standing cat-cow", detail: "Stand with soft knees, hands on your thighs. Round your back like a cat, then arch it. 4 slow times.", focus: .spine),
        Exercise(id: "backbend", title: "Standing back bend", detail: "Stand up, palms on your lower back. Lean back gently, then come up. 5 times.", focus: .spine),
        Exercise(id: "pelvictilt", title: "Pelvic tilts", detail: "Stand with soft knees, hands on your hips. Tilt your pelvis forward and back. 8 slow times.", focus: .spine),
        Exercise(id: "rolldown", title: "Roll down, roll up", detail: "Stand tall. Roll down to the floor one vertebra at a time, then roll back up. 2 times.", focus: .spine),
        Exercise(id: "kneehug", title: "Knee to chest", detail: "Stand up, hold the desk if you need. Pull one knee to your chest for 5 seconds, then the other.", focus: .spine),
        Exercise(id: "hipflexor", title: "Hip flexor stretch", detail: "Stand in a long step, back heel up. Tuck your pelvis, push the back hip forward. 15 seconds a side.", focus: .spine),
        Exercise(id: "hinge", title: "6 hip hinges", detail: "Stand with hands on your hips. Push your hips back with a straight back, then stand tall.", focus: .spine),
        Exercise(id: "reach", title: "Reach up, fold down", detail: "Stand tall. Stretch to the ceiling, then let your hands hang to the floor. 3 times.", focus: .spine),
        Exercise(id: "twists", title: "Torso twists", detail: "Stand up, arms loose. Turn left and right, 5 times each.", focus: .spine),
        Exercise(id: "hips", title: "Hip circles", detail: "Stand up, hands on your hips. 5 slow circles each way.", focus: .spine),
        Exercise(id: "sidebends", title: "Side bends", detail: "Stand with feet apart. Slide one hand down your leg, then the other. 6 times.", focus: .spine),
        // Everything else.
        Exercise(id: "squats", title: "8 slow squats", detail: "Stand with feet shoulder-width apart. Sit back, keep your heels on the floor."),
        Exercise(id: "shoulders", title: "Shoulder rolls", detail: "Stand up. 5 big circles forward, 5 back."),
        Exercise(id: "window", title: "Look far away", detail: "Stand up and walk to a window. Look at the farthest point you can see."),
        Exercise(id: "neck", title: "Neck stretch", detail: "Stand tall. Ear to shoulder, 10 seconds on each side."),
        Exercise(id: "calves", title: "10 calf raises", detail: "Stand up. Rise on your toes slowly, then lower your heels."),
        Exercise(id: "chest", title: "Open your chest", detail: "Stand up. Hands together behind your back, lift them and breathe deeply."),
        Exercise(id: "pushups", title: "6 desk push-ups", detail: "Stand facing the desk. Hands on its edge, body straight, chest to the desk."),
        Exercise(id: "march", title: "March in place", detail: "Stand up. Knees high, arms swinging, until the time is up."),
        Exercise(id: "lunges", title: "3 lunges per leg", detail: "Stand up. Big step forward, back knee towards the floor, step back."),
        Exercise(id: "stepjacks", title: "10 step jacks", detail: "Stand up. Step to the side and raise your arms, then step back."),
        Exercise(id: "water", title: "Get a glass of water", detail: "Stand up and walk to the kitchen. Drink a full glass."),
    ]

    /// One spine exercise, then one other. Nothing from the previous break repeats.
    public static func plan<R: RandomNumberGenerator>(
        duration: TimeInterval,
        avoiding previous: Set<String>,
        using rng: inout R
    ) -> BreakPlan {
        let spine = pick(.spine, avoiding: previous, using: &rng)
        let other = pick(.general, avoiding: previous, using: &rng)
        return BreakPlan(exercises: [spine, other], duration: duration)
    }

    public static func plan(duration: TimeInterval, avoiding previous: Set<String>) -> BreakPlan {
        var rng = SystemRandomNumberGenerator()
        return plan(duration: duration, avoiding: previous, using: &rng)
    }

    private static func pick<R: RandomNumberGenerator>(
        _ focus: Exercise.Focus,
        avoiding previous: Set<String>,
        using rng: inout R
    ) -> Exercise {
        let group = all.filter { $0.focus == focus }
        let fresh = group.filter { !previous.contains($0.id) }
        return (fresh.isEmpty ? group : fresh).randomElement(using: &rng) ?? all[0]
    }
}
