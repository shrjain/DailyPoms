import Foundation

/// Pomodoro summary for a single calendar day.
struct DayProgress: Identifiable {
    var day: Date
    var count: Int
    var goal: Int
    var totalMinutes: Int

    var id: Date { day }
    var isGoalMet: Bool { goal > 0 && count >= goal }
    var fraction: Double { goal <= 0 ? 0 : min(Double(count) / Double(goal), 1.0) }
}

/// Pure streak and history calculations over plain values,
/// kept free of SwiftData so the rules are easy to verify.
///
/// Streak rules:
/// - A day meets its goal ("Day won") when `count >= dailyGoal`.
/// - Today is forgiven while it is still in progress: an incomplete
///   today does not break the current streak until the day ends.
///
/// Days are calendar days in `calendar`. Every incoming date is
/// normalized with `startOfDay` in that calendar before comparison,
/// so sessions stored in another time zone still match a local
/// calendar day after travel.
enum Stats {
    /// One lookback window for Today, History, and the widget, so
    /// the streak numbers can never disagree between screens.
    static let lookbackDays = 366

    /// Days of row history History lists (stats use `lookbackDays`).
    static let historyListDays = 60

    typealias SessionInfo = (day: Date, durationMinutes: Int)

    /// Builds per-day progress for the given days (any order).
    static func progressByDay(
        sessions: [SessionInfo],
        dailyGoal: Int,
        days: [Date],
        calendar: Calendar = .current
    ) -> [DayProgress] {
        let clampedGoal = max(dailyGoal, 1)
        var countsByDay: [TimeInterval: Int] = [:]
        var minutesByDay: [TimeInterval: Int] = [:]

        for session in sessions {
            let key = calendar.startOfDay(for: session.day).timeIntervalSince1970
            countsByDay[key, default: 0] += 1
            minutesByDay[key, default: 0] += max(session.durationMinutes, 0)
        }

        return days.map { rawDay in
            let day = calendar.startOfDay(for: rawDay)
            let key = day.timeIntervalSince1970
            return DayProgress(
                day: day,
                count: countsByDay[key, default: 0],
                goal: clampedGoal,
                totalMinutes: minutesByDay[key, default: 0]
            )
        }
    }

    /// Consecutive goal-met days ending today (or yesterday if today's
    /// goal is not met yet). `progressDescending` must start with today
    /// and contain every day with no gaps.
    static func currentStreak(progressDescending: [DayProgress]) -> Int {
        var daysToCheck = progressDescending
        if let today = daysToCheck.first, !today.isGoalMet {
            daysToCheck.removeFirst()
        }
        var streak = 0
        for day in daysToCheck {
            guard day.isGoalMet else { break }
            streak += 1
        }
        return streak
    }

    /// Longest run of consecutive goal-met days anywhere in the list.
    /// `progressAscending` must contain every day with no gaps.
    static func bestStreak(progressAscending: [DayProgress]) -> Int {
        var best = 0
        var running = 0
        for day in progressAscending {
            if day.isGoalMet {
                running += 1
                best = max(best, running)
            } else {
                running = 0
            }
        }
        return best
    }

    /// The `count` most recent days including today, most recent
    /// first. Steps one calendar day at a time so the result is
    /// always gap-free across DST boundaries.
    static func recentDays(count: Int, endingToday today: Date, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        var days: [Date] = [calendar.startOfDay(for: today)]
        while days.count < count {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: days[days.count - 1]) else {
                break
            }
            days.append(calendar.startOfDay(for: previous))
        }
        return days
    }

    /// Concise human-readable duration (e.g. "25m", "1h 15m", "2h").
    static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours)h" : "\(hours)h \(rem)m"
    }
}
