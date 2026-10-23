import Foundation
import Testing
@testable import SixtyCore

/// Short durations keep the tests readable: 60 s of work, 10 s warning, 10 s break,
/// 30 s away threshold, 5 s grace after a call.
private let timing = Timing(
    workInterval: 60,
    warningDuration: 10,
    breakDuration: 10,
    awayThreshold: 30,
    callGrace: 5,
    breakWatchdog: 20
)

private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

/// Drives the machine with one tick per second and records every transition except `.none`.
private struct Driver {
    var machine = BreakMachine(timing: timing)
    var clock: TimeInterval = 0
    var log: [Transition] = []

    var now: Date { start.addingTimeInterval(clock) }

    mutating func run(seconds: Int, idle: TimeInterval = 0, inCall: Bool = false) {
        for _ in 0..<seconds {
            step(idle: idle, inCall: inCall)
            clock += 1
        }
    }

    mutating func step(idle: TimeInterval = 0, inCall: Bool = false) {
        let transition = machine.tick(Moment(now: now, idleSeconds: idle, inCall: inCall))
        if transition != .none { log.append(transition) }
    }
}

@Suite("BreakMachine")
struct BreakMachineTests {
    @Test func countsActiveTimeAndWarnsAfterTheInterval() {
        var d = Driver()
        d.run(seconds: 60)
        #expect(d.machine.phase == .working)
        #expect(d.machine.workedSeconds == 59)

        d.run(seconds: 2)
        #expect(d.log == [.warningStarted])
        #expect(d.machine.phase == .warning(endsAt: start.addingTimeInterval(60 + 10)))
    }

    @Test func shortIdleStillCountsAsWork() {
        var d = Driver()
        d.run(seconds: 62, idle: 29)
        #expect(d.log == [.warningStarted])
    }

    @Test func walkingAwayResetsTheCounter() {
        var d = Driver()
        d.run(seconds: 40)
        d.step(idle: 30)
        #expect(d.log == [.reset])
        #expect(d.machine.workedSeconds == 0)
        #expect(d.machine.phase == .working)
    }

    @Test func idleDuringACallIsNotAway() {
        var d = Driver()
        d.run(seconds: 40, idle: 200, inCall: true)
        #expect(d.log.isEmpty)
        #expect(d.machine.workedSeconds == 39)
    }

    @Test func sleepingResetsTheCounterEvenInACall() {
        var d = Driver()
        d.run(seconds: 40)
        d.clock += 30 // the Mac slept, no ticks
        d.step(inCall: true)
        #expect(d.log == [.reset])
        #expect(d.machine.workedSeconds == 0)
    }

    @Test func aCallAtDueTimePostponesTheBreak() {
        var d = Driver()
        d.run(seconds: 62, inCall: true)
        #expect(d.log == [.postponed])
        #expect(d.machine.phase == .postponed(callEndedAt: nil))
    }

    @Test func afterTheCallItWaitsTheGraceThenWarns() {
        var d = Driver()
        d.run(seconds: 62, inCall: true)
        d.run(seconds: 5)
        #expect(d.log == [.postponed])
        d.run(seconds: 1)
        #expect(d.log == [.postponed, .warningStarted])
    }

    @Test func aNewCallDuringTheGraceRestartsIt() {
        var d = Driver()
        d.run(seconds: 62, inCall: true)
        d.run(seconds: 3)
        d.run(seconds: 1, inCall: true)
        d.run(seconds: 5)
        #expect(d.log == [.postponed])
        d.run(seconds: 1)
        #expect(d.log == [.postponed, .warningStarted])
    }

    @Test func aCallDuringTheWarningPostponesTheBreak() {
        var d = Driver()
        d.run(seconds: 62)
        d.run(seconds: 1, inCall: true)
        #expect(d.log == [.warningStarted, .postponed])
    }

    @Test func theWarningEndsInABreak() {
        var d = Driver()
        d.run(seconds: 61) // warning starts at t = 60
        d.run(seconds: 10)
        #expect(d.log == [.warningStarted, .breakStarted])
        #expect(d.machine.phase == .onBreak(endsAt: start.addingTimeInterval(70 + 10)))
    }

    @Test func theBreakEndsAndANewCycleStarts() {
        var d = Driver()
        d.run(seconds: 81)
        #expect(d.log == [.warningStarted, .breakStarted, .breakFinished])
        #expect(d.machine.phase == .working)
        #expect(d.machine.workedSeconds == 0)
    }

    @Test func callsAndIdleDuringABreakChangeNothing() {
        var d = Driver()
        d.run(seconds: 71)
        d.run(seconds: 9, idle: 100, inCall: true)
        #expect(d.log == [.warningStarted, .breakStarted])
        #expect(d.machine.isOnBreak)
    }

    @Test func endBreakEarlyWorksOnlyDuringABreak() {
        var d = Driver()
        let whileWorking = d.machine.endBreakEarly()
        #expect(whileWorking == false)
        d.run(seconds: 71)
        let duringBreak = d.machine.endBreakEarly()
        #expect(duringBreak == true)
        #expect(d.machine.phase == .working)
        #expect(d.machine.workedSeconds == 0)
    }

    @Test func restoredProgressContinuesTheCycle() {
        var d = Driver(machine: BreakMachine(timing: timing, workedSeconds: 59))
        d.run(seconds: 2)
        #expect(d.log == [.warningStarted])
    }

    @Test func aClockJumpBackwardsDoesNotCountNegativeTime() {
        var d = Driver()
        d.run(seconds: 10)
        d.clock -= 3600
        d.step()
        #expect(d.machine.workedSeconds == 9)
    }

    @Test func secondsUntilBreak() {
        var d = Driver()
        d.run(seconds: 21)
        #expect(d.machine.secondsUntilBreak == 40)
    }
}
