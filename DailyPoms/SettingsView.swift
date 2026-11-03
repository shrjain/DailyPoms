import SwiftUI
import SwiftData
import UIKit

/// Configure daily pom target, default chunk durations, screen-awake
/// behavior, reminders, widget privacy, data export/erasure, and app info.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @Query(sort: \FocusSession.startedAt, order: .reverse) private var allSessions: [FocusSession]

    @AppStorage(SharedConstants.dailyGoalKey) private var dailyGoal = SharedConstants.defaultDailyGoal
    @AppStorage("focusDurationMinutes") private var focusDurationMinutes = 25
    @AppStorage("shortBreakMinutes") private var shortBreakMinutes = 5
    @AppStorage("longBreakMinutes") private var longBreakMinutes = 15
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("timerCompletionAlertEnabled") private var timerCompletionAlertEnabled = true

    @AppStorage("morningReminderEnabled") private var morningEnabled = false
    @AppStorage("eveningReminderEnabled") private var eveningEnabled = false
    @AppStorage("morningReminderMinutes") private var morningMinutes = 9 * 60
    @AppStorage("eveningReminderMinutes") private var eveningMinutes = 20 * 60
    @AppStorage("hasSeenNotificationPriming") private var hasSeenPriming = false
    @AppStorage(SharedConstants.widgetHidesLabelsKey) private var widgetHidesLabels = false

    @State private var permissionDenied = false
    @State private var schedulingFailed = false
    @State private var showPriming = false
    @State private var showEraseConfirmation = false
    @State private var userMessage: String?

    private static let focusOptions = [15, 20, 25, 30, 45, 50, 60]
    private static let shortBreakOptions = [3, 5, 10]
    private static let longBreakOptions = [10, 15, 20, 30]

    private var settingsSignature: String {
        "\(morningEnabled)|\(morningMinutes)|\(eveningEnabled)|\(eveningMinutes)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $dailyGoal, in: 1...16) {
                        HStack {
                            Text("Daily target")
                            Spacer()
                            Text("\(dailyGoal) \(dailyGoal == 1 ? "pom" : "poms")")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Picker("Default focus chunk", selection: $focusDurationMinutes) {
                        ForEach(Self.focusOptions, id: \.self) { mins in
                            Text("\(mins) min").tag(mins)
                        }
                    }

                    Picker("Short break", selection: $shortBreakMinutes) {
                        ForEach(Self.shortBreakOptions, id: \.self) { mins in
                            Text("\(mins) min").tag(mins)
                        }
                    }

                    Picker("Long break (every 4th)", selection: $longBreakMinutes) {
                        ForEach(Self.longBreakOptions, id: \.self) { mins in
                            Text("\(mins) min").tag(mins)
                        }
                    }
                } header: {
                    Text("Daily Poms & Chunks")
                } footer: {
                    Text("Reaching your daily target counts the day toward your streak. You can also pick quick chunk lengths (15m, 25m, 45m, 60m) right on the Today tab.")
                }

                Section {
                    Toggle("Keep screen awake while running", isOn: $keepScreenAwake)
                    Toggle("Alert when timer finishes", isOn: $timerCompletionAlertEnabled)
                } header: {
                    Text("On-Screen Timer")
                } footer: {
                    Text("Keeping the screen awake lets you watch your chunk of time count down on your desk without your iPhone locking.")
                }

                remindersSection

                Section {
                    Toggle("Hide session labels in widget", isOn: $widgetHidesLabels)
                } header: {
                    Text("Widget")
                } footer: {
                    Text("When on, the widget shows counts and durations only, keeping your session labels off the Home and Lock Screens.")
                }

                Section {
                    ShareLink(item: csvText) {
                        Label("Export history (CSV)", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showEraseConfirmation = true
                    } label: {
                        Label("Erase All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Your Data")
                } footer: {
                    Text("Your history is kept for about a year. Erasing removes all recorded poms and streaks on this iPhone.")
                }

                Section {
                    if let url = AppLinks.privacyPolicy {
                        Link(destination: url) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                    }
                    if let url = AppLinks.support {
                        Link(destination: url) {
                            Label("Support & Help", systemImage: "questionmark.circle")
                        }
                    }
                    LabeledContent("Version", value: versionText)
                    LabeledContent("Accounts", value: "None — no sign-in")
                    LabeledContent("Streak rule", value: "Daily target met")
                } header: {
                    Text("About")
                } footer: {
                    Text("Everything is stored on this iPhone and never sent to a server. If Apple device backup is on, your backup may include this app's data.")
                }
            }
            .navigationTitle("Settings")
            .task(id: settingsSignature) {
                await reconcileReminders(requestIfNeeded: true)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await reconcileReminders(requestIfNeeded: false) }
                }
            }
            .confirmationDialog(
                "Daily reminders",
                isPresented: $showPriming,
                titleVisibility: .visible
            ) {
                Button("Allow Notifications") {
                    hasSeenPriming = true
                    Task { await requestAndSchedule() }
                }
                Button("Not Now", role: .cancel) {
                    hasSeenPriming = true
                    morningEnabled = false
                    eveningEnabled = false
                }
            } message: {
                Text("Daily Poms can send quiet local nudges in the morning and evening, plus an alert when a timer chunk finishes. Nothing leaves your iPhone.")
            }
            .confirmationDialog(
                "Erase all data?",
                isPresented: $showEraseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Erase Everything", role: .destructive) { eraseAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All recorded poms, history, and streaks on this iPhone will be permanently deleted.")
            }
            .alert("Daily Poms", isPresented: Binding(
                get: { userMessage != nil },
                set: { if !$0 { userMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(userMessage ?? "")
            }
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Morning nudge", isOn: $morningEnabled)
            if morningEnabled && !permissionDenied {
                DatePicker("Morning time", selection: timeBinding($morningMinutes),
                           displayedComponents: .hourAndMinute)
            }
            Toggle("Evening check-in", isOn: $eveningEnabled)
            if eveningEnabled && !permissionDenied {
                DatePicker("Evening time", selection: timeBinding($eveningMinutes),
                           displayedComponents: .hourAndMinute)
            }
            if permissionDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Open iPhone Settings", systemImage: "gearshape")
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(remindersFooter)
        }
    }

    private var remindersFooter: String {
        if permissionDenied {
            return String(localized: "Notifications are turned off for Daily Poms. Turn them on in iPhone Settings, then come back — they'll reschedule automatically.")
        }
        if schedulingFailed {
            return String(localized: "Those reminders couldn't be scheduled. Toggle one off and on to try again.")
        }
        return String(localized: "A nudge to start your first focus chunk, and one in the evening. The evening check-in stays quiet once your daily target is met.")
    }

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var csvText: String {
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let isoFormatter = ISO8601DateFormatter()
        var lines = ["day,started_at,duration_minutes,label"]
        for session in allSessions.reversed() {
            let dayString = dayFormatter.string(from: session.day)
            let startedString = isoFormatter.string(from: session.startedAt)
            lines.append("\(dayString),\(startedString),\(session.durationMinutes),\(csvEscaped(session.label))")
        }
        return lines.joined(separator: "\n")
    }

    private func csvEscaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private func eraseAllData() {
        for session in allSessions {
            modelContext.delete(session)
        }
        do {
            try modelContext.save()
            SharedStore.refreshSnapshot(sessions: [], dailyGoal: dailyGoal)
            userMessage = String(localized: "All data has been erased.")
        } catch {
            AppLog.app.error("Erase failed: \(String(describing: error), privacy: .public)")
            userMessage = String(localized: "Couldn't erase your data. Please try again.")
        }
    }

    private func reconcileReminders(requestIfNeeded: Bool) async {
        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }

        guard morningEnabled || eveningEnabled else {
            Reminders.cancelAllReminders()
            permissionDenied = false
            schedulingFailed = false
            return
        }

        switch await Reminders.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            permissionDenied = false
            schedulingFailed = !(await Reminders.reschedule(
                morningEnabled: morningEnabled, morningMinutes: morningMinutes,
                eveningEnabled: eveningEnabled, eveningMinutes: eveningMinutes
            ))
        case .denied:
            permissionDenied = true
            Reminders.cancelAllReminders()
        case .notDetermined:
            if !hasSeenPriming {
                showPriming = true
            } else if requestIfNeeded {
                await requestAndSchedule()
            }
        @unknown default:
            break
        }
    }

    private func requestAndSchedule() async {
        if await Reminders.requestAuthorization() {
            permissionDenied = false
            schedulingFailed = !(await Reminders.reschedule(
                morningEnabled: morningEnabled, morningMinutes: morningMinutes,
                eveningEnabled: eveningEnabled, eveningMinutes: eveningMinutes
            ))
        } else {
            permissionDenied = true
            Reminders.cancelAllReminders()
        }
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes.wrappedValue / 60,
                    minute: minutes.wrappedValue % 60,
                    second: 0, of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
}
