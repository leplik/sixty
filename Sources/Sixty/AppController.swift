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

    private var updater: Updater?
    private var timer: Timer?
    private var signal: CallSignal?
    private var plan: BreakPlan?
    private var lastExerciseIDs: Set<String> = []
    private var savedAt = Date.distantPast

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
        blocker.onEscape = { [weak self] in self?.escape() }
        blocker.onWatchdog = { [weak self] in self?.watchdogFired() }
        if !demo, Updater.isSupported {
            updater = Updater { [weak self] in
                guard let self else { return }
                self.store.save(self.stats)
                self.saveWork(Date())
            }
        }
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
        signal = calls.signal(at: now)
        let moment = Moment(now: now, idleSeconds: presence.idleSeconds(at: now), inCall: signal != nil)
        handle(machine.tick(moment))

        switch machine.phase {
        case .warning: warning.update(now: now)
        case .onBreak: blocker.update(now: now)
        case .working, .postponed: break
        }
        menu.render(menuContent(now: now))
        updater?.tick(now: now, phase: machine.phase)

        let age = now.timeIntervalSince(savedAt)
        if age >= 10 || age < 0 { saveWork(now) }
    }

    private func handle(_ transition: Transition) {
        switch transition {
        case .none:
            break
        case .warningStarted:
            let plan = Exercises.plan(duration: timing.breakDuration, avoiding: lastExerciseIDs)
            self.plan = plan
            lastExerciseIDs = Set(plan.exercises.map(\.id))
            if case .warning(let endsAt) = machine.phase { warning.show(endsAt: endsAt, plan: plan) }
        case .postponed, .reset:
            warning.hide()
        case .breakStarted:
            warning.hide()
            if case .onBreak(let endsAt) = machine.phase {
                let left = stats.escapesLeft
                blocker.show(
                    endsAt: endsAt,
                    plan: plan ?? Exercises.plan(duration: timing.breakDuration, avoiding: lastExerciseIDs),
                    phrase: left > 0 ? EscapePhrase.make() : nil,
                    escapesLeft: left,
                    watchdogAfter: timing.breakWatchdog
                )
            }
        case .breakFinished:
            blocker.hide()
            stats.recordBreak()
            store.save(stats)
            saveWork(Date())
        }
    }

    private func escape() {
        guard machine.isOnBreak, stats.recordEscape() else { return }
        machine.endBreakEarly()
        blocker.hide()
        store.save(stats)
        saveWork(Date())
        menu.render(menuContent(now: Date()))
    }

    /// The lock is already gone. Bring the state machine in line; the break counts.
    private func watchdogFired() {
        guard machine.endBreakEarly() else { return }
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
