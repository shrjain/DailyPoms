import Foundation
import OSLog
import UserNotifications

/// Schedules local notifications for timer completion and optional
/// daily morning/evening reminders.
enum Reminders {
    private static let logger = Logger(subsystem: "com.shrainik.dailypoms", category: "reminders")

    static let timerCompletionID = "dailypoms.timer.completion"
    static let morningID = "dailypoms.morning"
    static let eveningID = "dailypoms.evening"
    static let eveningTomorrowID = "dailypoms.evening.tomorrow"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Authorization request failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: - Active Timer Notification

    static func scheduleTimerCompletion(
        endDate: Date,
        isFocus: Bool,
        durationMinutes: Int,
        label: String
    ) async {
        guard UserDefaults.standard.bool(forKey: "timerCompletionAlertEnabled") else { return }
        let seconds = endDate.timeIntervalSinceNow
        guard seconds > 1 else { return }

        var status = await authorizationStatus()
        if status == .notDetermined {
            _ = await requestAuthorization()
            status = await authorizationStatus()
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [timerCompletionID])

        let content = UNMutableNotificationContent()
        if isFocus {
            content.title = String(localized: "Pom complete")
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            content.body = trimmed.isEmpty
                ? String(localized: "\(durationMinutes)-minute focus chunk finished. Time for a break.")
                : String(localized: "\(durationMinutes)m on \"\(trimmed)\" finished. Time for a break.")
        } else {
            content.title = String(localized: "Break finished")
            content.body = String(localized: "Ready for your next focus chunk?")
        }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: timerCompletionID,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            logger.error("Schedule timer completion failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func cancelTimerCompletion() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [timerCompletionID]
        )
    }

    // MARK: - Daily Reminders

    static func cancelAllReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [morningID, eveningID, eveningTomorrowID]
        )
    }

    @discardableResult
    static func reschedule(
        morningEnabled: Bool,
        morningMinutes: Int,
        eveningEnabled: Bool,
        eveningMinutes: Int
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [morningID, eveningID, eveningTomorrowID]
        )
        var success = true
        if morningEnabled {
            success = await scheduleDaily(
                id: morningID,
                content: morningContent(),
                minutes: morningMinutes,
                center: center
            ) && success
        }
        if eveningEnabled {
            success = await scheduleDaily(
                id: eveningID,
                content: eveningContent(),
                minutes: eveningMinutes,
                center: center
            ) && success
        }
        return success
    }

    /// Once today's pom goal is met, swaps tonight's repeating
    /// evening reminder for a one-off tomorrow so tonight stays quiet.
    static func applyTodayCompletion(
        isGoalMet: Bool,
        eveningEnabled: Bool,
        eveningMinutes: Int
    ) async {
        guard eveningEnabled else { return }
        let center = UNUserNotificationCenter.current()
        guard await authorizationStatus() == .authorized else { return }

        if isGoalMet {
            center.removePendingNotificationRequests(withIdentifiers: [eveningID, eveningTomorrowID])
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            var components = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
            components.hour = eveningMinutes / 60
            components.minute = eveningMinutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: eveningTomorrowID,
                content: eveningContent(),
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                logger.error("Tomorrow check-in schedule failed: \(String(describing: error), privacy: .public)")
            }
        } else {
            let pending = await center.pendingNotificationRequests()
            if !pending.contains(where: { $0.identifier == eveningID }) {
                center.removePendingNotificationRequests(withIdentifiers: [eveningTomorrowID])
                await scheduleDaily(
                    id: eveningID,
                    content: eveningContent(),
                    minutes: eveningMinutes,
                    center: center
                )
            }
        }
    }

    private static func morningContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Today's poms")
        content.body = String(localized: "Pick a chunk of time and get your first focus session underway.")
        content.sound = .default
        return content
    }

    private static func eveningContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Evening check-in")
        content.body = String(localized: "Still a pom or two short of today's goal? A quick chunk can win the day.")
        content.sound = .default
        return content
    }

    @discardableResult
    private static func scheduleDaily(
        id: String,
        content: UNMutableNotificationContent,
        minutes: Int,
        center: UNUserNotificationCenter
    ) async -> Bool {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            logger.error("Schedule \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
