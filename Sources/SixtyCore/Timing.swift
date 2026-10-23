import Foundation

/// Durations that drive the break cycle. The app ships one fixed set; there are no user settings.
public struct Timing: Sendable, Equatable {
    /// Active work time before a break is due.
    public var workInterval: TimeInterval
    /// How long the corner countdown shows before the screens lock.
    public var warningDuration: TimeInterval
    /// How long the screens stay locked.
    public var breakDuration: TimeInterval
    /// No input for this long, outside a call, means you already took a break.
    /// Reading or watching for a while is still sitting, so the real cycle uses 20 minutes.
    public var awayThreshold: TimeInterval
    /// Wait after a call ends before the warning starts.
    public var callGrace: TimeInterval
    /// Hard upper limit for one lock, even if the state machine fails to end it.
    public var breakWatchdog: TimeInterval

    public init(
        workInterval: TimeInterval,
        warningDuration: TimeInterval,
        breakDuration: TimeInterval,
        awayThreshold: TimeInterval,
        callGrace: TimeInterval,
        breakWatchdog: TimeInterval
    ) {
        self.workInterval = workInterval
        self.warningDuration = warningDuration
        self.breakDuration = breakDuration
        self.awayThreshold = awayThreshold
        self.callGrace = callGrace
        self.breakWatchdog = breakWatchdog
    }

    /// The only cycle users get: 60 min of work, 60 s warning, 60 s break.
    public static let standard = Timing(
        workInterval: 60 * 60,
        warningDuration: 60,
        breakDuration: 60,
        awayThreshold: 20 * 60,
        callGrace: 2 * 60,
        breakWatchdog: 90
    )

    /// Short cycle for development and manual QA (`SIXTY_DEMO=1`).
    public static let demo = Timing(
        workInterval: 20,
        warningDuration: 5,
        breakDuration: 10,
        awayThreshold: 5 * 60,
        callGrace: 10,
        breakWatchdog: 30
    )
}
