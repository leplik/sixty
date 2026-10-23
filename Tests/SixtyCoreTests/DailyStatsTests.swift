import Foundation
import Testing
@testable import SixtyCore

@Suite("DailyStats")
struct DailyStatsTests {
    @Test func countsBreaksAndLimitsEscapes() {
        var s = DailyStats(day: "2026-10-23")
        s.recordBreak()
        s.recordBreak()
        #expect(s.breaks == 2)
        #expect(s.escapesLeft == 2)
        let first = s.recordEscape()
        let second = s.recordEscape()
        let third = s.recordEscape()
        #expect(first && second && !third)
        #expect(s.escapes == 2)
        #expect(s.escapesLeft == 0)
    }

    @Test func aNewDayStartsFromZero() {
        var s = DailyStats(day: "2026-10-23")
        s.recordBreak()
        _ = s.recordEscape()
        s.roll(to: "2026-10-23")
        #expect(s.breaks == 1)
        s.roll(to: "2026-10-24")
        #expect(s == DailyStats(day: "2026-10-24"))
    }

    @Test func dayKeyUsesTheGivenCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        // 2026-10-23 22:30 UTC is already 2026-10-24 in Warsaw (UTC+2).
        let date = Date(timeIntervalSince1970: 1_792_794_600)
        #expect(DailyStats.dayKey(for: date, calendar: calendar) == "2026-10-24")
    }

    @Test func survivesCodableRoundTrip() throws {
        var s = DailyStats(day: "2026-10-23")
        s.recordBreak()
        _ = s.recordEscape()
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(DailyStats.self, from: data) == s)
    }
}

@Suite("Exercises")
struct ExercisesTests {
    @Test func aBreakIsOneSpineExerciseThenOneOther() {
        var rng = SeededGenerator(state: 1)
        for _ in 0..<200 {
            let plan = Exercises.plan(duration: 60, avoiding: [], using: &rng)
            #expect(plan.exercises.count == 2)
            #expect(plan.exercises[0].focus == .spine)
            #expect(plan.exercises[1].focus == .general)
        }
    }

    @Test func nothingRepeatsFromThePreviousBreak() {
        var rng = SeededGenerator(state: 2)
        var previous: Set<String> = []
        for _ in 0..<200 {
            let ids = Set(Exercises.plan(duration: 60, avoiding: previous, using: &rng).exercises.map(\.id))
            #expect(ids.isDisjoint(with: previous))
            previous = ids
        }
    }

    @Test func bothGroupsAreBigEnoughToVary() {
        #expect(Exercises.all.filter { $0.focus == .spine }.count >= 6)
        #expect(Exercises.all.filter { $0.focus == .general }.count >= 6)
    }

    @Test func halvesOfTheBreak() {
        let plan = Exercises.plan(duration: 60, avoiding: [])
        #expect(plan.segment == 30)
        #expect(plan.index(at: 0) == 0)
        #expect(plan.index(at: 29.9) == 0)
        #expect(plan.index(at: 30) == 1)
        #expect(plan.index(at: 75) == 1)
        #expect(plan.index(at: -3) == 0)
        #expect(plan.secondsLeftInSegment(at: 0) == 30)
        #expect(plan.secondsLeftInSegment(at: 12) == 18)
        #expect(plan.secondsLeftInSegment(at: 45) == 15)
        #expect(plan.secondsLeftInSegment(at: 70) == 0)
    }

    @Test func idsAreUniqueAndTextIsPresent() {
        #expect(Set(Exercises.all.map(\.id)).count == Exercises.all.count)
        #expect(Exercises.all.count >= 10)
        for e in Exercises.all {
            #expect(!e.title.isEmpty)
            #expect(!e.detail.isEmpty)
        }
    }

    @Test func everyExerciseIsDoneStanding() {
        for e in Exercises.all {
            #expect(e.detail.hasPrefix("Stand"), "\(e.id): \(e.detail)")
        }
    }
}
