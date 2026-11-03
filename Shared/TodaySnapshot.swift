import Foundation
import OSLog

/// Constants shared by the app and the widget extension.
enum SharedConstants {
    static let appGroupID = "group.com.shrainik.dailypoms"
    static let snapshotKey = "todaySnapshot"
    /// UserDefaults key (app sandbox): hide session labels in the widget.
    static let widgetHidesLabelsKey = "widgetHidesLabels"
    /// UserDefaults key (app sandbox): daily target poms.
    static let dailyGoalKey = "dailyGoalPomodoros"
    static let defaultDailyGoal = 4
}

/// One completed focus chunk as shown in the medium widget.
struct SessionSnapshot: Codable, Equatable {
    var durationMinutes: Int
    var label: String
}

/// A lightweight, Codable copy of "today" that the app writes to the
/// App Group after every change. The widget renders this snapshot only,
/// so it never has to open the SwiftData store.
struct TodaySnapshot: Codable, Equatable {
    var formatVersion: Int = 1
    var day: Date
    var completedCount: Int
    var dailyGoal: Int
    var totalMinutes: Int
    var streak: Int
    var recentSessions: [SessionSnapshot]

    var isGoalMet: Bool { dailyGoal > 0 && completedCount >= dailyGoal }

    var progressFraction: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(Double(completedCount) / Double(dailyGoal), 1.0)
    }

    static var empty: TodaySnapshot {
        TodaySnapshot(
            day: Calendar.current.startOfDay(for: Date()),
            completedCount: 0,
            dailyGoal: SharedConstants.defaultDailyGoal,
            totalMinutes: 0,
            streak: 0,
            recentSessions: []
        )
    }

    /// Representative sample so the widget gallery and previews show
    /// the real layout instead of an empty state.
    static var previewSample: TodaySnapshot {
        TodaySnapshot(
            day: Calendar.current.startOfDay(for: Date()),
            completedCount: 3,
            dailyGoal: 4,
            totalMinutes: 75,
            streak: 5,
            recentSessions: [
                SessionSnapshot(durationMinutes: 25, label: "Deep work"),
                SessionSnapshot(durationMinutes: 25, label: "Write notes"),
                SessionSnapshot(durationMinutes: 25, label: "Read chapter"),
            ]
        )
    }

    /// The snapshot rolled forward to `date`'s calendar day. A fresh
    /// day starts at zero poms. The streak survives rollover only
    /// when the immediately previous day met its goal (today's
    /// forgiveness then applies to the new day); any older or
    /// incomplete snapshot resets it to zero.
    func rolledOver(to date: Date, calendar: Calendar = .current) -> TodaySnapshot {
        let targetDay = calendar.startOfDay(for: date)
        let snapshotDay = calendar.startOfDay(for: day)
        if snapshotDay == targetDay { return self }
        if snapshotDay > targetDay { return self }
        let dayGap = calendar.dateComponents([.day], from: snapshotDay, to: targetDay).day ?? 0
        return TodaySnapshot(
            formatVersion: formatVersion,
            day: targetDay,
            completedCount: 0,
            dailyGoal: dailyGoal,
            totalMinutes: 0,
            streak: (dayGap == 1 && isGoalMet) ? streak : 0,
            recentSessions: []
        )
    }

    /// One-line VoiceOver summary used by the widgets.
    var accessibilitySummary: String {
        var parts = [
            String(localized: "\(completedCount) of \(dailyGoal) poms"),
            String(localized: "\(totalMinutes) minutes focused"),
        ]
        if isGoalMet {
            parts.append(String(localized: "Daily goal met"))
        }
        if streak > 0 {
            parts.append(String(localized: "\(streak)-day streak"))
        }
        return parts.joined(separator: ", ")
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, day, completedCount, dailyGoal, totalMinutes, streak, recentSessions
    }

    init(
        formatVersion: Int = 1,
        day: Date,
        completedCount: Int,
        dailyGoal: Int,
        totalMinutes: Int,
        streak: Int,
        recentSessions: [SessionSnapshot]
    ) {
        self.formatVersion = formatVersion
        self.day = day
        self.completedCount = completedCount
        self.dailyGoal = max(dailyGoal, 1)
        self.totalMinutes = totalMinutes
        self.streak = streak
        self.recentSessions = recentSessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 0
        day = try container.decode(Date.self, forKey: .day)
        completedCount = try container.decode(Int.self, forKey: .completedCount)
        dailyGoal = max(try container.decode(Int.self, forKey: .dailyGoal), 1)
        totalMinutes = try container.decode(Int.self, forKey: .totalMinutes)
        streak = try container.decode(Int.self, forKey: .streak)
        recentSessions = try container.decodeIfPresent([SessionSnapshot].self, forKey: .recentSessions) ?? []
    }
}

/// Reads and writes the snapshot in App Group UserDefaults.
enum SnapshotStore {
    private static let logger = Logger(subsystem: "com.shrainik.dailypoms", category: "snapshot")

    @discardableResult
    static func save(_ snapshot: TodaySnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: SharedConstants.appGroupID) else {
            logger.error("App Group UserDefaults unavailable; snapshot not saved")
            return false
        }
        do {
            let data = try JSONEncoder().encode(snapshot)
            guard defaults.data(forKey: SharedConstants.snapshotKey) != data else { return false }
            defaults.set(data, forKey: SharedConstants.snapshotKey)
            return true
        } catch {
            logger.error("Snapshot encode failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    static func load() -> TodaySnapshot {
        guard let defaults = UserDefaults(suiteName: SharedConstants.appGroupID) else {
            logger.error("App Group UserDefaults unavailable; returning empty snapshot")
            return .empty
        }
        guard let data = defaults.data(forKey: SharedConstants.snapshotKey) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(TodaySnapshot.self, from: data)
        } catch {
            logger.error("Snapshot decode failed: \(String(describing: error), privacy: .public)")
            return .empty
        }
    }
}
