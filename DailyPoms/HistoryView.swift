import Combine
import SwiftUI
import SwiftData
import UIKit

/// Streak and focus stats over the shared 366-day lookback, plus a
/// day-by-day record of the last 60 days.
struct HistoryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \FocusSession.startedAt, order: .reverse) private var allSessions: [FocusSession]
    @AppStorage(SharedConstants.dailyGoalKey) private var dailyGoal = SharedConstants.defaultDailyGoal

    @State private var currentDay: Date = DayHelper.today

    var body: some View {
        let days = Stats.recentDays(count: Stats.lookbackDays, endingToday: currentDay)
        let progress = Stats.progressByDay(
            sessions: allSessions.map { (day: $0.day, durationMinutes: $0.durationMinutes) },
            dailyGoal: dailyGoal,
            days: days
        )

        NavigationStack {
            Group {
                if allSessions.isEmpty {
                    ContentUnavailableView(
                        "No poms yet",
                        systemImage: "timer",
                        description: Text("Complete your first focus chunk on the Today tab to start tracking your daily count and streak.")
                    )
                } else {
                    historyList(progress: progress)
                }
            }
            .navigationTitle("History")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { currentDay = DayHelper.today }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            currentDay = DayHelper.today
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            currentDay = DayHelper.today
        }
    }

    private func historyList(progress: [DayProgress]) -> some View {
        let currentStreak = Stats.currentStreak(progressDescending: progress)
        let bestStreak = Stats.bestStreak(progressAscending: progress.reversed())
        let listProgress = Array(progress.prefix(Stats.historyListDays))
        let goalDays = listProgress.filter(\.isGoalMet).count
        let last7 = progress.prefix(7)
        let last7Count = last7.reduce(0) { $0 + $1.count }
        let last7Minutes = last7.reduce(0) { $0 + $1.totalMinutes }
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]

        return List {
            Section {
                LazyVGrid(columns: columns, spacing: 12) {
                    StatCard(
                        title: "Current streak",
                        value: "\(currentStreak)",
                        unit: currentStreak == 1 ? "day" : "days",
                        systemImage: "flame.fill",
                        color: .orange,
                        accessibilityText: String(localized: "Current streak: \(currentStreak) days")
                    )
                    StatCard(
                        title: "Best streak",
                        value: "\(bestStreak)",
                        unit: bestStreak == 1 ? "day" : "days",
                        systemImage: "trophy.fill",
                        color: .orange,
                        accessibilityText: String(localized: "Best streak: \(bestStreak) days")
                    )
                    StatCard(
                        title: "Goal days",
                        value: "\(goalDays)",
                        unit: "last 60 days",
                        systemImage: "checkmark.seal.fill",
                        color: .green,
                        accessibilityText: String(localized: "Goal days: \(goalDays) in the last 60 days")
                    )
                    StatCard(
                        title: "Last 7 days",
                        value: "\(last7Count)",
                        unit: "\(Stats.formatMinutes(last7Minutes)) focused",
                        systemImage: "timer",
                        color: .blue,
                        accessibilityText: String(
                            localized: "Last 7 days: \(last7Count) poms, \(Stats.formatMinutes(last7Minutes)) focused"
                        )
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Last \(Stats.historyListDays) days") {
                ForEach(listProgress.filter { $0.count > 0 || DayHelper.isSameDay($0.day, currentDay) }) { day in
                    DayRow(progress: day, isToday: DayHelper.isSameDay(day.day, currentDay))
                }
            }

            Section {
                Text("A goal day means you reached your daily pom target. Today never breaks a streak while the day is still in progress. History is kept for about a year.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatCard: View {
    let title: LocalizedStringKey
    let value: String
    let unit: String
    let systemImage: String
    let color: Color
    let accessibilityText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(.primary)
            }
            .font(.caption.bold())

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.title.bold())
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(value).font(.title.bold())
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

private struct DayRow: View {
    let progress: DayProgress
    let isToday: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: progress.isGoalMet ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(progress.isGoalMet ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(isToday ? "Today" : progress.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                ProgressView(value: progress.fraction)
                    .tint(progress.isGoalMet ? .green : .accentColor)
                    .accessibilityHidden(true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(progress.count)/\(progress.goal)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(Stats.formatMinutes(progress.totalMinutes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let dayName = isToday
            ? String(localized: "Today")
            : progress.day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let base = String(localized: "\(dayName): \(progress.count) of \(progress.goal) poms, \(progress.totalMinutes) minutes")
        return progress.isGoalMet ? base + String(localized: ", goal met") : base
    }
}
