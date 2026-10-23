import AppKit
import SixtyCore

/// Wires the state machine to the devices and the UI. Ticks once per second.
@MainActor
final class AppController {
    private let timing: Timing
    private let demo: Bool
    private let store: Store
    private var machine: BreakMachine
    private var stats: DailyStats

    private let presence = PresenceMonitor()
    private let calls = CallDetector()
    private let menu = MenuBarController()
    private let warning = WarningPanel()
    private let blocker = Blocker()

    #if !APP_STORE
    private var updater: Updater?
    #endif
    private var timer: Timer?
    private var signal: CallSignal?
    private var plan: BreakPlan?
    private var lastExerciseIDs: Set<String> = []
    private var savedAt = Date.distantPast
    private var heartbeatAt = Date.distantPast

    init(timing: Timing, store: Store, demo: Bool) {
        let now = Date()
        self.timing = timing
        self.demo = demo
        self.store = store
        machine = BreakMachine(
            timing: timing,
            workedSeconds: store.restoredWork(now: now, awayThreshold: timing.awayThreshold)
        )
        stats = store.stats(today: DailyStats.dayKey(for: now))
        Log.cycle.notice("""
            started \(Links.version, privacy: .public), \(demo ? "demo" : "standard", privacy: .public) cycle, \
            restored \(Int(self.machine.workedSeconds / 60)) min of work, breaks today \(self.stats.breaks)
            """)
        blocker.onEscape = { [weak self] in self?.escape() }
        blocker.onWatchdog = { [weak self] in self?.watchdogFired() }
        menu.onBreakNow = { [weak self] in self?.takeBreakNow() }
        #if !APP_STORE
        if !demo, Updater.isSupported {
            updater = Updater { [weak self] in
                guard let self else { return }
                self.store.save(self.stats)
                self.saveWork(Date())
            }
        }
        #endif
    }

    func start() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // `.common` keeps the timer running while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func tick() {
        let now = Date()
        stats.roll(to: DailyStats.dayKey(for: now))
        let newSignal = calls.signal(at: now)
        if newSignal != signal {
            Log.calls.notice("call: \(Self.describe(self.signal), privacy: .public) -> \(Self.describe(newSignal), privacy: .public)")
        }
        signal = newSignal
        let idle = presence.idleSeconds(at: now)
        let workedBefore = machine.workedSeconds
        handle(machine.tick(Moment(now: now, idleSeconds: idle, inCall: signal != nil)), workedBefore: workedBefore, idle: idle)

        switch machine.phase {
        case .warning: warning.update(now: now)
        case .onBreak: blocker.update(now: now)
        case .working, .postponed: break
        }
        menu.render(menuContent(now: now))
        #if !APP_STORE
        updater?.tick(now: now, phase: machine.phase)
        #endif

        let age = now.timeIntervalSince(savedAt)
        if age >= 10 || age < 0 { saveWork(now) }

        let sinceHeartbeat = now.timeIntervalSince(heartbeatAt)
        if sinceHeartbeat >= 600 || sinceHeartbeat < 0 {
            heartbeatAt = now
            Log.cycle.notice("""
                state: \(self.describe(self.machine.phase, now: now), privacy: .public), \
                worked \(Int(self.machine.workedSeconds / 60)) min, idle \(Int(idle)) s, \
                call \(Self.describe(self.signal), privacy: .public), breaks today \(self.stats.breaks)
                """)
        }
    }

    private func handle(_ transition: Transition, workedBefore: TimeInterval = 0, idle: TimeInterval = 0) {
        switch transition {
        case .none:
            break
        case .warningStarted:
            let plan = Exercises.plan(duration: timing.breakDuration, avoiding: lastExerciseIDs)
            self.plan = plan
            lastExerciseIDs = Set(plan.exercises.map(\.id))
            if case .warning(let endsAt) = machine.phase { warning.show(endsAt: endsAt, plan: plan) }
            Log.cycle.notice("warning: break in \(Int(self.timing.warningDuration)) s, \(Self.describe(plan), privacy: .public)")
        case .postponed:
            warning.hide()
            Log.cycle.notice("break due, waiting for the call: \(Self.describe(self.signal), privacy: .public)")
        case .reset(let reason):
            warning.hide()
            switch reason {
            case .idle:
                Log.cycle.notice("""
                    work counter reset after \(Int(workedBefore / 60)) min: no input for \(Int(idle / 60)) min\
                    \(self.presence.isLocked ? ", screen locked" : "", privacy: .public)
                    """)
            case .sleep:
                Log.cycle.notice("work counter reset after \(Int(workedBefore / 60)) min: the Mac slept")
            }
        case .breakStarted:
            warning.hide()
            if case .onBreak(let endsAt) = machine.phase {
                let left = stats.escapesLeft
                let plan = plan ?? Exercises.plan(duration: timing.breakDuration, avoiding: lastExerciseIDs)
                blocker.show(
                    endsAt: endsAt,
                    plan: plan,
                    phrase: left > 0 ? EscapePhrase.make() : nil,
                    escapesLeft: left,
                    watchdogAfter: timing.breakWatchdog
                )
                Log.cycle.notice("break started: \(Self.describe(plan), privacy: .public), emergency exits left \(left)")
            }
        case .breakFinished:
            blocker.hide()
            stats.recordBreak()
            store.save(stats)
            saveWork(Date())
            Log.cycle.notice("break finished, breaks today \(self.stats.breaks)")
        }
    }

    private static func describe(_ signal: CallSignal?) -> String {
        switch signal {
        case nil: "none"
        case .camera: "camera"
        case .microphone(let app): "\(app) (microphone)"
        case .speaker(let app): "\(app) (speaker)"
        }
    }

    private static func describe(_ plan: BreakPlan) -> String {
        plan.exercises.map(\.id).joined(separator: " + ")
    }

    private func describe(_ phase: Phase, now: Date) -> String {
        switch phase {
        case .working: "working, next break in \(Int(ceil(machine.secondsUntilBreak / 60))) min"
        case .warning(let endsAt): "warning, \(Int(endsAt.timeIntervalSince(now))) s left"
        case .postponed(let ended): ended == nil ? "postponed, call running" : "postponed, call ended"
        case .onBreak(let endsAt): "on break, \(Int(endsAt.timeIntervalSince(now))) s left"
        }
    }

    /// "Take a Break Now": a fresh plan, then the normal break.
    func takeBreakNow() {
        Log.cycle.notice("Take a Break Now chosen in the menu")
        let plan = Exercises.plan(duration: timing.breakDuration, avoiding: lastExerciseIDs)
        self.plan = plan
        lastExerciseIDs = Set(plan.exercises.map(\.id))
        handle(machine.startBreakNow(at: Date()))
        menu.render(menuContent(now: Date()))
    }

    private func escape() {
        guard machine.isOnBreak, stats.recordEscape() else { return }
        Log.cycle.notice("emergency exit used, \(self.stats.escapesLeft) left today")
        machine.endBreakEarly()
        blocker.hide()
        store.save(stats)
        saveWork(Date())
        menu.render(menuContent(now: Date()))
    }

    /// The lock is already gone. Bring the state machine in line; the break counts.
    private func watchdogFired() {
        guard machine.endBreakEarly() else { return }
        Log.cycle.error("watchdog ended a break that ran too long")
        stats.recordBreak()
        store.save(stats)
        saveWork(Date())
    }

    private func saveWork(_ now: Date) {
        store.saveWork(machine.workedSeconds, now: now)
        savedAt = now
    }

    private func menuContent(now: Date) -> MenuContent {
        var title = ""
        var symbol = "figure.stand"
        var status: String

        switch machine.phase {
        case .working:
            let minutes = Int(ceil(machine.secondsUntilBreak / 60))
            title = String(format: L("%ldm"), minutes)
            status = String(format: L("Next break in %ld min"), minutes)
        case .warning(let endsAt):
            let seconds = max(0, Int(ceil(endsAt.timeIntervalSince(now))))
            title = String(format: L("%lds"), seconds)
            symbol = "figure.walk"
            status = String(format: L("Break in %ld s"), seconds)
        case .postponed(let callEndedAt):
            symbol = "phone.fill"
            if callEndedAt != nil {
                status = L("Call ended. Break soon.")
            } else {
                switch signal {
                case .camera: status = L("Break waits: the camera is on")
                case .microphone(let app), .speaker(let app): status = String(format: L("Break waits: call in %@"), app)
                case nil: status = L("Call ended. Break soon.")
                }
            }
        case .onBreak:
            symbol = "figure.walk"
            status = L("On break")
        }
        if demo { status += " · demo" }

        return MenuContent(
            title: title,
            symbol: symbol,
            status: status,
            breaksToday: String(format: L("Breaks today: %ld"), stats.breaks),
            escapesLeft: String(format: L("Emergency exits left today: %ld of %ld"), stats.escapesLeft, DailyStats.escapeLimit)
        )
    }
}
