import Foundation
import OSLog
import SwiftData

/// Version 1 of the stored schema for Daily Poms focus sessions.
enum DailyPomsSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [FocusSession.self]
    }

    /// Records one completed focus chunk (pom).
    /// `day` is normalized to the local calendar's start-of-day; always
    /// compare days with `Calendar.isDate(_:inSameDayAs:)` or
    /// `calendar.startOfDay(for:)`, never raw equality, so time-zone
    /// travel cannot break matching.
    @Model
    final class FocusSession {
        @Attribute(.unique) var id: UUID
        var day: Date
        var startedAt: Date
        var durationMinutes: Int
        var label: String

        init(
            day: Date = DayHelper.today,
            startedAt: Date = Date(),
            durationMinutes: Int,
            label: String = ""
        ) {
            self.id = UUID()
            self.day = DayHelper.startOfDay(day)
            self.startedAt = startedAt
            self.durationMinutes = max(durationMinutes, 1)
            self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var displayLabel: String {
            label.isEmpty ? String(localized: "Focus chunk") : label
        }
    }
}

typealias FocusSession = DailyPomsSchemaV1.FocusSession

enum DailyPomsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [DailyPomsSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// Calendar-day helpers. Days are compared as calendar days in the
/// user's current time zone, never as absolute instants.
enum DayHelper {
    private static let logger = Logger(subsystem: "com.shrainik.dailypoms", category: "calendar")

    static var today: Date { Calendar.current.startOfDay(for: Date()) }

    static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }

    static func day(byAddingDays days: Int, to date: Date) -> Date {
        if let result = Calendar.current.date(byAdding: .day, value: days, to: date) {
            return result
        }
        logger.error("Calendar could not add \(days, privacy: .public) days to a date; returning input")
        return date
    }
}
