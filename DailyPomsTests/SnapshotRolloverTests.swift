import XCTest
@testable import DailyPoms

/// The widget must never present yesterday's state as today's.
final class SnapshotRolloverTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func snapshot(day: Date, completed: Int, goal: Int, streak: Int) -> TodaySnapshot {
        TodaySnapshot(
            day: day,
            completedCount: completed,
            dailyGoal: goal,
            totalMinutes: completed * 25,
            streak: streak,
            recentSessions: [SessionSnapshot(durationMinutes: 25, label: "Deep work")]
        )
    }

    func testSameDayPassesThrough() {
        let original = snapshot(day: day(2026, 11, 1), completed: 2, goal: 4, streak: 3)
        let rolled = original.rolledOver(to: day(2026, 11, 1), calendar: utc)
        XCTAssertEqual(rolled.completedCount, 2)
        XCTAssertEqual(rolled.streak, 3)
    }

    func testGoalMetYesterdayKeepsStreakAndClearsCounts() {
        let original = snapshot(day: day(2026, 10, 31), completed: 4, goal: 4, streak: 5)
        let rolled = original.rolledOver(to: day(2026, 11, 1), calendar: utc)
        XCTAssertEqual(rolled.completedCount, 0)
        XCTAssertEqual(rolled.totalMinutes, 0)
        XCTAssertTrue(rolled.recentSessions.isEmpty)
        XCTAssertEqual(rolled.streak, 5)
    }

    func testIncompleteYesterdayResetsStreak() {
        let original = snapshot(day: day(2026, 10, 31), completed: 2, goal: 4, streak: 5)
        let rolled = original.rolledOver(to: day(2026, 11, 1), calendar: utc)
        XCTAssertEqual(rolled.streak, 0)
    }

    func testSnapshotOlderThanYesterdayResetsStreak() {
        let original = snapshot(day: day(2026, 10, 28), completed: 4, goal: 4, streak: 9)
        let rolled = original.rolledOver(to: day(2026, 11, 1), calendar: utc)
        XCTAssertEqual(rolled.streak, 0)
        XCTAssertEqual(rolled.completedCount, 0)
    }
}
