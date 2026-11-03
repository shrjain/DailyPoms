import XCTest
@testable import DailyPoms

/// Pins every README streak rule plus calendar edge cases (time-zone
/// travel, DST, streaks longer than the 60-day History list window,
/// today forgiveness, and focused minutes totals).
final class StatsTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testTodayForgiveness() {
        let progress = [
            DayProgress(day: Date(), count: 1, goal: 4, totalMinutes: 25), // today, in progress
            DayProgress(day: Date(), count: 4, goal: 4, totalMinutes: 100),
            DayProgress(day: Date(), count: 5, goal: 4, totalMinutes: 125),
            DayProgress(day: Date(), count: 2, goal: 4, totalMinutes: 50),
        ]
        XCTAssertEqual(Stats.currentStreak(progressDescending: progress), 2)
    }

    func testStreakLongerThanSixtyDays() {
        let today = day(2026, 11, 1, in: utc)
        let days = Stats.recentDays(count: Stats.lookbackDays, endingToday: today, calendar: utc)
        let sessions = days.prefix(70).flatMap { d in
            [
                (day: d, durationMinutes: 25),
                (day: d, durationMinutes: 25),
                (day: d, durationMinutes: 25),
                (day: d, durationMinutes: 25),
            ]
        }
        let progress = Stats.progressByDay(sessions: sessions, dailyGoal: 4, days: days, calendar: utc)
        XCTAssertEqual(Stats.currentStreak(progressDescending: progress), 70)
        XCTAssertEqual(Stats.bestStreak(progressAscending: progress.reversed()), 70)
        XCTAssertEqual(progress.first?.totalMinutes, 100)
    }

    func testRecentDaysAreGapFreeAcrossDST() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let today = day(2026, 3, 10, in: newYork)
        let days = Stats.recentDays(count: 6, endingToday: today, calendar: newYork)
        XCTAssertEqual(days.count, 6)
        for index in 0..<(days.count - 1) {
            let gap = newYork.dateComponents([.day], from: days[index + 1], to: days[index]).day
            XCTAssertEqual(gap, 1, "Days must be consecutive calendar days")
        }
    }

    func testSessionStoredInAnotherTimeZoneMatchesLocalCalendarDay() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let tokyoMidnight = day(2026, 11, 1, in: tokyo)
        let laDays = [day(2026, 10, 31, in: losAngeles), day(2026, 11, 1, in: losAngeles)]
        let progress = Stats.progressByDay(
            sessions: [(day: tokyoMidnight, durationMinutes: 45)],
            dailyGoal: 2,
            days: laDays,
            calendar: losAngeles
        )
        XCTAssertEqual(progress[0].count, 1, "Session should land on Oct 31 in Los Angeles")
        XCTAssertEqual(progress[0].totalMinutes, 45)
        XCTAssertEqual(progress[1].count, 0)
    }

    func testFormatMinutes() {
        XCTAssertEqual(Stats.formatMinutes(25), "25m")
        XCTAssertEqual(Stats.formatMinutes(60), "1h")
        XCTAssertEqual(Stats.formatMinutes(75), "1h 15m")
    }
}
