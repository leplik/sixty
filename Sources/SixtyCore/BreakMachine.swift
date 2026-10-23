import Foundation

/// Where the break cycle is. See docs/SPEC.md, section 3.
public enum Phase: Equatable, Sendable {
    /// Counting active work time.
    case working
    /// The corner countdown is visible; the lock starts at `endsAt`.
    case warning(endsAt: Date)
    /// A break is due, but a call is active (`callEndedAt == nil`) or ended recently.
    case postponed(callEndedAt: Date?)
    /// All screens are locked until `endsAt`.
    case onBreak(endsAt: Date)
}

/// What the app sees on one tick.
public struct Moment: Equatable, Sendable {
    public var now: Date
    /// Seconds since the last keyboard or mouse input, or since the screen was locked.
    public var idleSeconds: TimeInterval
    public var inCall: Bool

    public init(now: Date, idleSeconds: TimeInterval, inCall: Bool) {
        self.now = now
        self.idleSeconds = idleSeconds
        self.inCall = inCall
    }
}

/// A change the UI must react to.
public enum Transition: Equatable, Sendable {
    case none
    case warningStarted
    case postponed
    case breakStarted
    case breakFinished
    /// You were away (or the Mac slept): the cycle starts again from zero.
    case reset
}

/// The break cycle as a pure value type. The app calls `tick` once per second.
public struct BreakMachine: Sendable {
    public let timing: Timing
    public private(set) var phase: Phase = .working
    public private(set) var workedSeconds: TimeInterval
    private var lastTick: Date?

    public init(timing: Timing = .standard, workedSeconds: TimeInterval = 0) {
        self.timing = timing
        self.workedSeconds = max(0, workedSeconds)
    }

    public var secondsUntilBreak: TimeInterval {
        max(0, timing.workInterval - workedSeconds)
    }

    public var isOnBreak: Bool {
        if case .onBreak = phase { return true }
        return false
    }

    public mutating func tick(_ o: Moment) -> Transition {
        // A clock that jumps backwards must not subtract work time.
        let gap = lastTick.map { max(0, o.now.timeIntervalSince($0)) } ?? 0
        lastTick = o.now

        // A break always runs to its end: calls and idle time do not change it.
        if case .onBreak(let endsAt) = phase {
            guard o.now >= endsAt else { return .none }
            startNewCycle()
            return .breakFinished
        }

        let slept = gap >= timing.awayThreshold
        let walkedAway = !o.inCall && o.idleSeconds >= timing.awayThreshold
        if slept || walkedAway {
            let hadProgress = phase != .working || workedSeconds > 0
            startNewCycle()
            return hadProgress ? .reset : .none
        }

        switch phase {
        case .working:
            workedSeconds += gap
            guard workedSeconds >= timing.workInterval else { return .none }
            return o.inCall ? postpone() : startWarning(at: o.now)

        case .warning(let endsAt):
            if o.inCall { return postpone() }
            guard o.now >= endsAt else { return .none }
            phase = .onBreak(endsAt: o.now.addingTimeInterval(timing.breakDuration))
            return .breakStarted

        case .postponed(let callEndedAt):
            if o.inCall {
                phase = .postponed(callEndedAt: nil)
                return .none
            }
            guard let ended = callEndedAt else {
                phase = .postponed(callEndedAt: o.now)
                return .none
            }
            guard o.now.timeIntervalSince(ended) >= timing.callGrace else { return .none }
            return startWarning(at: o.now)

        case .onBreak:
            return .none // handled above
        }
    }

    /// "Take a Break Now" from the menu. More breaks are always allowed; it never skips one.
    /// The work counter resets when this break ends, as after any break.
    public mutating func startBreakNow(at now: Date) -> Transition {
        guard !isOnBreak else { return .none }
        lastTick = now
        phase = .onBreak(endsAt: now.addingTimeInterval(timing.breakDuration))
        return .breakStarted
    }

    /// Ends a break before its time: the emergency phrase or the watchdog.
    /// Returns `false` if no break is running.
    @discardableResult
    public mutating func endBreakEarly() -> Bool {
        guard isOnBreak else { return false }
        startNewCycle()
        return true
    }

    private mutating func startWarning(at now: Date) -> Transition {
        phase = .warning(endsAt: now.addingTimeInterval(timing.warningDuration))
        return .warningStarted
    }

    private mutating func postpone() -> Transition {
        phase = .postponed(callEndedAt: nil)
        return .postponed
    }

    private mutating func startNewCycle() {
        phase = .working
        workedSeconds = 0
    }
}
