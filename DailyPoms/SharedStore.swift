import Foundation
import OSLog
import SwiftData
import WidgetKit

enum AppLog {
    static let store = Logger(subsystem: "com.shrainik.dailypoms", category: "store")
    static let app = Logger(subsystem: "com.shrainik.dailypoms", category: "app")
}

/// Ways opening the on-device store can fail. Surfaced to the user
/// with retry/reset instead of silently using a different store.
enum StoreError: Error {
    case appGroupUnavailable
    case openFailed(underlying: Error)
}

extension StoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return String(localized: "The shared storage used by the app and its widget isn't available.")
        case .openFailed(let underlying):
            return underlying.localizedDescription
        }
    }
}

/// Owns the SwiftData container (stored in the App Group so the data
/// sits next to the widget snapshot) and the widget snapshot writer.
enum SharedStore {
    static var groupStoreURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.appGroupID)?
            .appendingPathComponent("DailyPoms.store")
    }

    static func makeContainer() throws -> ModelContainer {
        guard let storeURL = groupStoreURL else {
            AppLog.store.fault("App Group container unavailable; refusing to open a fallback store")
            throw StoreError.appGroupUnavailable
        }
        let schema = Schema(versionedSchema: DailyPomsSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: DailyPomsMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            AppLog.store.error("ModelContainer open failed: \(String(describing: error), privacy: .public)")
            throw StoreError.openFailed(underlying: error)
        }
    }

    /// Deletes the group store files. Used only by the explicit
    /// user-confirmed reset on the store-error screen.
    static func deleteStoreFiles() {
        guard let storeURL = groupStoreURL else { return }
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let url = storeURL.deletingLastPathComponent()
                .appendingPathComponent(storeURL.lastPathComponent + suffix)
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    AppLog.store.error("Store file delete failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// Recomputes today's snapshot from current data and writes it to
    /// the App Group, reloading widget timelines only when the
    /// snapshot actually changed. Returns the current streak.
    @discardableResult
    static func refreshSnapshot(
        sessions: [FocusSession],
        dailyGoal: Int
    ) -> Int {
        let today = DayHelper.today
        let clampedGoal = max(dailyGoal, 1)
        let todaysSessions = sessions
            .filter { DayHelper.isSameDay($0.day, today) }
            .sorted { $0.startedAt > $1.startedAt }

        let sessionInfos = sessions.map { (day: $0.day, durationMinutes: $0.durationMinutes) }
        let days = Stats.recentDays(count: Stats.lookbackDays, endingToday: today)
        let progress = Stats.progressByDay(sessions: sessionInfos, dailyGoal: clampedGoal, days: days)
        let streak = Stats.currentStreak(progressDescending: progress)

        let hideLabels = UserDefaults.standard.bool(forKey: SharedConstants.widgetHidesLabelsKey)
        let snapshot = TodaySnapshot(
            day: today,
            completedCount: todaysSessions.count,
            dailyGoal: clampedGoal,
            totalMinutes: todaysSessions.reduce(0) { $0 + $1.durationMinutes },
            streak: streak,
            recentSessions: todaysSessions.prefix(4).enumerated().map { index, session in
                SessionSnapshot(
                    durationMinutes: session.durationMinutes,
                    label: hideLabels
                        ? String(localized: "Pom \(todaysSessions.count - index)")
                        : session.displayLabel
                )
            }
        )
        if SnapshotStore.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        return streak
    }

    /// Launch housekeeping: normalizes stored days to the current
    /// calendar and prunes sessions outside the retention window
    /// (about a year) so storage stays bounded.
    @MainActor
    static func runMaintenance(context: ModelContext) {
        do {
            var changed = false
            let cutoff = DayHelper.day(
                byAddingDays: -(Stats.lookbackDays + 34),
                to: DayHelper.today
            )
            for session in try context.fetch(FetchDescriptor<FocusSession>()) {
                let normalized = DayHelper.startOfDay(session.day)
                if session.day != normalized {
                    session.day = normalized
                    changed = true
                }
                if normalized < cutoff {
                    context.delete(session)
                    changed = true
                }
            }
            if changed {
                try context.save()
                AppLog.store.notice("Maintenance normalized/pruned stored sessions")
            }
        } catch {
            AppLog.store.error("Maintenance failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Creates the one shared container off the main thread, exactly
/// once even if several scenes ask at the same time.
actor ContainerLoader {
    static let shared = ContainerLoader()

    private var inFlight: Task<ModelContainer, Error>?

    func load() async throws -> ModelContainer {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task.detached(priority: .userInitiated) {
            try SharedStore.makeContainer()
        }
        inFlight = task
        do {
            return try await task.value
        } catch {
            inFlight = nil
            throw error
        }
    }

    func reset() {
        inFlight = nil
    }
}
