import Foundation

/// Breaks and emergency exits for one local calendar day.
public struct DailyStats: Codable, Equatable, Sendable {
    public static let escapeLimit = 2

    /// Local day in `yyyy-MM-dd` form.
    public private(set) var day: String
    public private(set) var breaks = 0
    public private(set) var escapes = 0

    public init(day: String) {
        self.day = day
    }

    public var escapesLeft: Int { max(0, Self.escapeLimit - escapes) }

    /// Starts from zero if `today` is a new day.
    public mutating func roll(to today: String) {
        if today != day { self = DailyStats(day: today) }
    }

    public mutating func recordBreak() {
        breaks += 1
    }

    /// Returns `false` if the daily limit is used up.
    public mutating func recordEscape() -> Bool {
        guard escapesLeft > 0 else { return false }
        escapes += 1
        return true
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
