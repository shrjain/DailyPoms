import Combine
import SwiftUI
import SwiftData
import UIKit

enum TimerMode: String, CaseIterable, Identifiable {
    case focus
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    var tintColor: Color {
        switch self {
        case .focus: .accentColor
        case .shortBreak: .teal
        case .longBreak: .indigo
        }
    }

    var icon: String {
        switch self {
        case .focus: "timer"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
        }
    }
}

/// The main screen: today's pom progress, the on-screen chunk
/// timer, and today's completed focus chunks.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \FocusSession.startedAt, order: .reverse) private var allSessions: [FocusSession]

    @AppStorage(SharedConstants.dailyGoalKey) private var dailyGoal = SharedConstants.defaultDailyGoal
    @AppStorage("focusDurationMinutes") private var defaultFocusMinutes = 25
    @AppStorage("shortBreakMinutes") private var shortBreakMinutes = 5
    @AppStorage("longBreakMinutes") private var longBreakMinutes = 15
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage(SharedConstants.widgetHidesLabelsKey) private var widgetHidesLabels = false

    // Persisted active-timer state so locking the screen or switching
    // apps never loses an in-progress chunk.
    @AppStorage("timerModeRaw") private var timerModeRaw: String = TimerMode.focus.rawValue
    @AppStorage("timerIsRunning") private var isRunning: Bool = false
    @AppStorage("timerEndTimestamp") private var timerEndTimestamp: Double = 0
    @AppStorage("timerPausedRemaining") private var pausedRemainingSeconds: Int = 25 * 60
    @AppStorage("timerTotalSeconds") private var totalChunkSeconds: Int = 25 * 60
    @SceneStorage("draftSessionLabel") private var draftLabel: String = ""

    @State private var currentDay: Date = DayHelper.today
    @State private var now: Date = Date()
    @State private var currentStreak = 0
    @State private var completionTrigger = false
    @State private var goalWonTrigger = false
    @State private var didRunMaintenance = false
    @State private var sessionToRename: FocusSession?
    @State private var renameText = ""
    @State private var userMessage: String?

    private static let quickChunks = [15, 25, 45, 60]
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var timerMode: TimerMode {
        get { TimerMode(rawValue: timerModeRaw) ?? .focus }
        nonmutating set { timerModeRaw = newValue.rawValue }
    }

    private var todaysSessions: [FocusSession] {
        allSessions.filter { DayHelper.isSameDay($0.day, currentDay) }
    }

    private var todaysCount: Int { todaysSessions.count }

    private var todaysMinutes: Int {
        todaysSessions.reduce(0) { $0 + $1.durationMinutes }
    }

    private var isGoalMet: Bool {
        dailyGoal > 0 && todaysCount >= dailyGoal
    }

    private var remainingSeconds: Int {
        if isRunning {
            let end = Date(timeIntervalSince1970: timerEndTimestamp)
            return max(Int(ceil(end.timeIntervalSince(now))), 0)
        }
        return max(pausedRemainingSeconds, 0)
    }

    private var isPausedMidChunk: Bool {
        !isRunning && remainingSeconds > 0 && remainingSeconds < totalChunkSeconds
    }

    private var ringProgress: Double {
        guard totalChunkSeconds > 0 else { return 0 }
        let elapsed = Double(totalChunkSeconds - remainingSeconds)
        return min(max(elapsed / Double(totalChunkSeconds), 0), 1)
    }

    private var recentDistinctLabels: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for session in allSessions {
            let trimmed = session.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
                if result.count == 4 { break }
            }
        }
        return result
    }

    private var snapshotSignature: String {
        let todayPart = todaysSessions.map {
            "\($0.id)|\($0.durationMinutes)|\($0.label)"
        }.joined(separator: ",")
        return "\(currentDay.timeIntervalSince1970)|\(dailyGoal)|\(allSessions.count)|\(todayPart)|\(widgetHidesLabels)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    headerView
                }

                Section {
                    timerCard
                }

                Section {
                    if todaysSessions.isEmpty {
                        Text("No completed chunks yet today. Start the timer above or log a finished chunk below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(todaysSessions) { session in
                            SessionRow(
                                session: session,
                                onRename: {
                                    sessionToRename = session
                                    renameText = session.label
                                },
                                onDelete: {
                                    deleteSession(session)
                                }
                            )
                        }
                    }

                    Menu {
                        ForEach(Self.quickChunks, id: \.self) { mins in
                            Button {
                                logManualChunk(minutes: mins)
                            } label: {
                                Label("Log \(mins)-minute pom", systemImage: "plus.circle")
                            }
                        }
                    } label: {
                        Label("Log a finished chunk", systemImage: "plus.circle")
                            .font(.subheadline.weight(.medium))
                    }
                    .accessibilityIdentifier("button.logChunk")
                } header: {
                    HStack {
                        Text("Today's chunks")
                        Spacer()
                        if todaysMinutes > 0 {
                            Text(Stats.formatMinutes(todaysMinutes) + " total")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
                .headerProminence(.increased)
            }
            .navigationTitle("Today")
        }
        .sensoryFeedback(.success, trigger: completionTrigger)
        .sensoryFeedback(.impact(weight: .heavy), trigger: goalWonTrigger)
        .onReceive(ticker) { tick in
            now = tick
            checkTimerFinishedIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                now = Date()
                currentDay = DayHelper.today
                checkTimerFinishedIfNeeded()
                updateIdleTimer()
            }
        }
        .onChange(of: isRunning) { _, _ in updateIdleTimer() }
        .onChange(of: keepScreenAwake) { _, _ in updateIdleTimer() }
        .onChange(of: defaultFocusMinutes) { _, newValue in
            if !isRunning && !isPausedMidChunk && timerMode == .focus {
                totalChunkSeconds = newValue * 60
                pausedRemainingSeconds = newValue * 60
            }
        }
        .onChange(of: shortBreakMinutes) { _, newValue in
            if !isRunning && !isPausedMidChunk && timerMode == .shortBreak {
                totalChunkSeconds = newValue * 60
                pausedRemainingSeconds = newValue * 60
            }
        }
        .onChange(of: longBreakMinutes) { _, newValue in
            if !isRunning && !isPausedMidChunk && timerMode == .longBreak {
                totalChunkSeconds = newValue * 60
                pausedRemainingSeconds = newValue * 60
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            currentDay = DayHelper.today
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            currentDay = DayHelper.today
            now = Date()
            checkTimerFinishedIfNeeded()
        }
        .onChange(of: snapshotSignature) { _, _ in refreshSnapshot() }
        .onAppear {
            now = Date()
            reconcileInitialTimerDuration()
            seedDemoDataIfRequested()
            if !didRunMaintenance {
                didRunMaintenance = true
                SharedStore.runMaintenance(context: modelContext)
            }
            checkTimerFinishedIfNeeded()
            updateIdleTimer()
            refreshSnapshot()
        }
        .alert("Edit chunk label", isPresented: Binding(
            get: { sessionToRename != nil },
            set: { if !$0 { sessionToRename = nil } }
        )) {
            TextField("Label (optional)", text: $renameText)
            Button("Save") {
                if let session = sessionToRename {
                    session.label = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    saveOrReport()
                }
                sessionToRename = nil
            }
            Button("Cancel", role: .cancel) { sessionToRename = nil }
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

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(currentDay, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if todaysMinutes > 0 {
                    Text("\(Stats.formatMinutes(todaysMinutes)) focused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(todaysCount) of \(dailyGoal)")
                    .font(.title2.bold())
                Text(dailyGoal == 1 ? "pom" : "poms")
                    .foregroundStyle(.secondary)
                Spacer()
                if currentStreak > 0 {
                    Label {
                        Text("\(currentStreak)-day streak")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.subheadline.bold())
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(localized: "\(todaysCount) of \(dailyGoal) poms")
                    + (currentStreak > 0 ? String(localized: ", \(currentStreak)-day streak") : "")
            )

            tomatoDotsRow

            ProgressView(value: Double(min(todaysCount, max(dailyGoal, 1))),
                         total: Double(max(dailyGoal, 1)))
                .tint(isGoalMet ? .green : .accentColor)

            if isGoalMet {
                Label {
                    Text("All poms done. Day won.")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                .font(.subheadline.bold())
            }
        }
        .padding(.vertical, 4)
    }

    private var tomatoDotsRow: some View {
        let totalDots = min(max(dailyGoal, todaysCount), 12)
        return HStack(spacing: 8) {
            ForEach(0..<totalDots, id: \.self) { index in
                let filled = index < todaysCount
                let isBonus = index >= dailyGoal
                Image(systemName: filled ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.headline)
                    .foregroundStyle(
                        filled
                            ? (isGoalMet ? Color.green : (isBonus ? Color.orange : Color.accentColor))
                            : Color.secondary.opacity(0.45)
                    )
            }
            if max(dailyGoal, todaysCount) > 12 {
                Text("+\(max(dailyGoal, todaysCount) - 12)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - On-Screen Timer Card

    private var timerCard: some View {
        VStack(spacing: 12) {
            modeSelector

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 11)

                Circle()
                    .trim(from: 0, to: 1.0 - ringProgress)
                    .stroke(
                        timerMode.tintColor,
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.35), value: ringProgress)

                VStack(spacing: 3) {
                    Label(timerMode.title, systemImage: timerMode.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(timerMode.tintColor)

                    Text(formatCountdown(remainingSeconds))
                        .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityIdentifier("timer.countdown")

                    Text(timerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
            }
            .frame(width: 184, height: 184)
            .padding(.top, 2)

            if timerMode == .focus && !isRunning && !isPausedMidChunk {
                chunkPresetPills
            }

            timerControls

            if timerMode == .focus {
                labelInputView
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private var modeSelector: some View {
        HStack(spacing: 6) {
            ForEach(TimerMode.allCases) { mode in
                let isSelected = timerMode == mode
                Button {
                    selectMode(mode)
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                Capsule().fill(mode.tintColor.opacity(0.16))
                            } else {
                                Capsule().fill(Color.secondary.opacity(0.08))
                            }
                        }
                        .foregroundStyle(isSelected ? mode.tintColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
            }
        }
    }

    private var chunkPresetPills: some View {
        HStack(spacing: 8) {
            ForEach(Self.quickChunks, id: \.self) { mins in
                let selected = totalChunkSeconds == mins * 60
                Button {
                    setChunkMinutes(mins)
                } label: {
                    Text("\(mins)m")
                        .font(.subheadline.weight(selected ? .bold : .medium).monospacedDigit())
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background {
                            Capsule().fill(
                                selected
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.12)
                            )
                        }
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "\(mins) minute chunk"))
            }
        }
    }

    private var labelInputView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("What is this chunk for? (optional)", text: $draftLabel)
                    .font(.subheadline)
                    .submitLabel(.done)
                if !draftLabel.isEmpty {
                    Button {
                        draftLabel = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear label")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            if !recentDistinctLabels.isEmpty && draftLabel.isEmpty && !isRunning {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recentDistinctLabels, id: \.self) { suggestion in
                            Button {
                                draftLabel = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var timerControls: some View {
        HStack(spacing: 12) {
            Button {
                toggleStartPause()
            } label: {
                Label(
                    isRunning ? "Pause" : (isPausedMidChunk ? "Resume" : "Start"),
                    systemImage: isRunning ? "pause.fill" : "play.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(timerMode.tintColor)
            .accessibilityIdentifier("timer.startPause")

            if isRunning || isPausedMidChunk {
                if timerMode == .focus {
                    Button {
                        finishFocusChunkEarly()
                    } label: {
                        Label("Log Done", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .accessibilityLabel("Complete and count this pom now")
                }

                Button(role: .destructive) {
                    resetTimer()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.headline)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reset timer")
            } else if timerMode != .focus {
                Button {
                    selectMode(.focus)
                } label: {
                    Text("Skip Break")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var timerSubtitle: String {
        if isRunning {
            let end = Date(timeIntervalSince1970: timerEndTimestamp)
            return String(localized: "Ends at \(end.formatted(date: .omitted, time: .shortened))")
        }
        if isPausedMidChunk {
            return String(localized: "Paused")
        }
        let mins = max(totalChunkSeconds / 60, 1)
        return timerMode == .focus
            ? String(localized: "\(mins)-minute focus chunk")
            : String(localized: "\(mins)-minute break")
    }

    // MARK: - Timer Actions

    private func reconcileInitialTimerDuration() {
        if !isRunning && !isPausedMidChunk {
            let minutes = defaultMinutes(for: timerMode)
            totalChunkSeconds = minutes * 60
            pausedRemainingSeconds = minutes * 60
        }
    }

    private func defaultMinutes(for mode: TimerMode) -> Int {
        switch mode {
        case .focus: return max(defaultFocusMinutes, 1)
        case .shortBreak: return max(shortBreakMinutes, 1)
        case .longBreak: return max(longBreakMinutes, 1)
        }
    }

    private func selectMode(_ mode: TimerMode) {
        guard !isRunning else { return }
        timerMode = mode
        let mins = defaultMinutes(for: mode)
        totalChunkSeconds = mins * 60
        pausedRemainingSeconds = mins * 60
    }

    private func setChunkMinutes(_ minutes: Int) {
        guard !isRunning else { return }
        totalChunkSeconds = minutes * 60
        pausedRemainingSeconds = minutes * 60
    }

    private func toggleStartPause() {
        now = Date()
        if isRunning {
            let left = remainingSeconds
            pausedRemainingSeconds = max(left, 1)
            isRunning = false
            timerEndTimestamp = 0
            Reminders.cancelTimerCompletion()
        } else {
            let secondsToRun = pausedRemainingSeconds > 0 ? pausedRemainingSeconds : totalChunkSeconds
            if totalChunkSeconds <= 0 {
                totalChunkSeconds = secondsToRun
            }
            let endDate = now.addingTimeInterval(TimeInterval(secondsToRun))
            timerEndTimestamp = endDate.timeIntervalSince1970
            isRunning = true
            let isFocus = (timerMode == .focus)
            let mins = max(totalChunkSeconds / 60, 1)
            let label = draftLabel
            Task {
                await Reminders.scheduleTimerCompletion(
                    endDate: endDate,
                    isFocus: isFocus,
                    durationMinutes: mins,
                    label: label
                )
            }
        }
    }

    private func resetTimer() {
        isRunning = false
        timerEndTimestamp = 0
        pausedRemainingSeconds = totalChunkSeconds
        Reminders.cancelTimerCompletion()
    }

    private func finishFocusChunkEarly() {
        guard timerMode == .focus else { return }
        let elapsedSeconds = totalChunkSeconds - remainingSeconds
        let recordedMinutes = max(Int(round(Double(max(elapsedSeconds, 60)) / 60.0)), 1)
        let fullMinutes = max(totalChunkSeconds / 60, 1)
        let finalMinutes = elapsedSeconds >= (totalChunkSeconds / 2) ? fullMinutes : recordedMinutes
        Reminders.cancelTimerCompletion()
        completeFocusChunk(durationMinutes: finalMinutes, completedAt: Date())
    }

    private func checkTimerFinishedIfNeeded() {
        guard isRunning else { return }
        let end = Date(timeIntervalSince1970: timerEndTimestamp)
        guard now >= end else { return }

        Reminders.cancelTimerCompletion()
        if timerMode == .focus {
            let mins = max(totalChunkSeconds / 60, 1)
            completeFocusChunk(durationMinutes: mins, completedAt: end)
        } else {
            isRunning = false
            timerEndTimestamp = 0
            completionTrigger.toggle()
            selectMode(.focus)
        }
    }

    private func completeFocusChunk(durationMinutes: Int, completedAt: Date) {
        let wasGoalMet = isGoalMet
        isRunning = false
        timerEndTimestamp = 0

        let sessionDay = DayHelper.startOfDay(completedAt)
        let session = FocusSession(
            day: sessionDay,
            startedAt: completedAt,
            durationMinutes: durationMinutes,
            label: draftLabel
        )
        modelContext.insert(session)
        saveOrReport()

        let newTodayCount = todaysCount
        if !wasGoalMet && newTodayCount >= dailyGoal {
            goalWonTrigger.toggle()
        } else {
            completionTrigger.toggle()
        }

        let nextMode: TimerMode = (newTodayCount > 0 && newTodayCount % 4 == 0) ? .longBreak : .shortBreak
        selectMode(nextMode)
    }

    private func logManualChunk(minutes: Int) {
        let wasGoalMet = isGoalMet
        let session = FocusSession(
            day: currentDay,
            startedAt: Date(),
            durationMinutes: minutes,
            label: draftLabel
        )
        modelContext.insert(session)
        saveOrReport()

        if !wasGoalMet && todaysCount >= dailyGoal {
            goalWonTrigger.toggle()
        } else {
            completionTrigger.toggle()
        }
    }

    private func deleteSession(_ session: FocusSession) {
        modelContext.delete(session)
        saveOrReport()
    }

    private func saveOrReport() {
        do {
            try modelContext.save()
        } catch {
            AppLog.app.error("Save failed: \(String(describing: error), privacy: .public)")
            userMessage = String(localized: "Couldn't save your changes. Please try again.")
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isRunning && keepScreenAwake
    }

    private func refreshSnapshot() {
        currentStreak = SharedStore.refreshSnapshot(
            sessions: allSessions,
            dailyGoal: dailyGoal
        )
        let eveningEnabled = UserDefaults.standard.bool(forKey: "eveningReminderEnabled")
        let eveningMinutes = UserDefaults.standard.integer(forKey: "eveningReminderMinutes")
        let goalMet = isGoalMet
        Task {
            await Reminders.applyTodayCompletion(
                isGoalMet: goalMet,
                eveningEnabled: eveningEnabled,
                eveningMinutes: eveningMinutes
            )
        }
    }

    private func formatCountdown(_ totalSeconds: Int) -> String {
        let clamped = max(totalSeconds, 0)
        let mins = clamped / 60
        let secs = clamped % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    /// Debug-only demo data for App Store screenshots and testing:
    /// launch with `-seedDemoData` (optionally `-seedAllDone`) on an empty store.
    private func seedDemoDataIfRequested() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-seedDemoData"), allSessions.isEmpty else { return }
        let labels = ["Deep work", "Write design doc", "Code review", "Read paper"]
        let allDoneToday = args.contains("-seedAllDone")

        for daysAgo in 1...12 {
            let day = DayHelper.day(byAddingDays: -daysAgo, to: DayHelper.today)
            let countForDay = (daysAgo == 4) ? 2 : 4
            for index in 0..<countForDay {
                let start = Calendar.current.date(byAdding: .hour, value: 9 + index * 2, to: day) ?? day
                modelContext.insert(FocusSession(
                    day: day,
                    startedAt: start,
                    durationMinutes: 25,
                    label: labels[index % labels.count]
                ))
            }
        }

        let todayTargetCount = allDoneToday ? dailyGoal : max(dailyGoal - 1, 2)
        for index in 0..<todayTargetCount {
            let start = Calendar.current.date(byAdding: .minute, value: -(todayTargetCount - index) * 35, to: Date()) ?? Date()
            modelContext.insert(FocusSession(
                day: DayHelper.today,
                startedAt: start,
                durationMinutes: 25,
                label: labels[index % labels.count]
            ))
        }
        saveOrReport()
        #endif
    }
}

/// One completed focus chunk row with tap-to-rename and a visible
/// delete button (horizontal swipes switch tabs).
private struct SessionRow: View {
    let session: FocusSession
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onRename) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayLabel)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(session.durationMinutes)m")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(session.displayLabel), \(session.durationMinutes) minutes")
            .accessibilityHint("Tap to edit label")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel(String(localized: "Delete \(session.displayLabel)"))
        }
    }
}
