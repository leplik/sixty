import Foundation
import SixtyCore

/// Keeps the work counter across restarts, so killing Sixty during the warning does not skip the break.
@MainActor
final class Store {
    private let defaults: UserDefaults

    init(demo: Bool) {
        defaults = demo ? UserDefaults(suiteName: "pro.saac.sixty.demo") ?? .standard : .standard
    }

    /// The saved counter, if it was saved recently. After a long gap you were away anyway.
    func restoredWork(now: Date, awayThreshold: TimeInterval) -> TimeInterval {
        let savedAt = defaults.double(forKey: Key.savedAt)
        guard savedAt > 0 else { return 0 }
        let age = now.timeIntervalSinceReferenceDate - savedAt
        guard age >= 0, age < awayThreshold else { return 0 }
        return defaults.double(forKey: Key.worked)
    }

    func saveWork(_ seconds: TimeInterval, now: Date) {
        defaults.set(seconds, forKey: Key.worked)
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: Key.savedAt)
    }

    func stats(today: String) -> DailyStats {
        guard let data = defaults.data(forKey: Key.stats),
              var stats = try? JSONDecoder().decode(DailyStats.self, from: data)
        else { return DailyStats(day: today) }
        stats.roll(to: today)
        return stats
    }

    func save(_ stats: DailyStats) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults.set(data, forKey: Key.stats)
    }

    private enum Key {
        static let worked = "workedSeconds"
        static let savedAt = "workedSavedAt"
        static let stats = "dailyStats"
    }
}
