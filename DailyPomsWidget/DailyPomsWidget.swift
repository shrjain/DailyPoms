import WidgetKit
import SwiftUI

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .previewSample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(
            date: Date(),
            snapshot: context.isPreview ? .previewSample : SnapshotStore.load()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: SnapshotStore.load())
        let nextMidnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 72
    let entry: SnapshotEntry

    private var snapshot: TodaySnapshot { entry.snapshot.rolledOver(to: entry.date) }

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular
    }

    var body: some View {
        if isAccessory {
            content.containerBackground(.clear, for: .widget)
        } else {
            content.containerBackground(.fill.tertiary, for: .widget)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .systemSmall:
            smallView
        default:
            mediumView
        }
    }

    private var circularView: some View {
        Gauge(
            value: Double(min(snapshot.completedCount, snapshot.dailyGoal)),
            in: 0...Double(max(snapshot.dailyGoal, 1))
        ) {
            Image(systemName: snapshot.isGoalMet ? "checkmark" : "timer")
        } currentValueLabel: {
            Text("\(snapshot.completedCount)")
        }
        .gaugeStyle(.accessoryCircular)
        .tint(snapshot.isGoalMet ? .green : .accentColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Daily Poms", systemImage: "timer")
                .font(.caption2.bold())
                .widgetAccentable()
            Text("\(snapshot.completedCount) of \(snapshot.dailyGoal) done")
                .font(.footnote.bold())
            Text(snapshot.isGoalMet
                 ? "Day won · \(snapshot.totalMinutes)m"
                 : "\(snapshot.totalMinutes)m focused")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
    }

    private var smallView: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: snapshot.progressFraction)
                    .stroke(snapshot.isGoalMet ? Color.green : Color.accentColor,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(snapshot.completedCount)/\(snapshot.dailyGoal)")
                        .font(.title3.bold().monospacedDigit())
                    if snapshot.totalMinutes > 0 {
                        Text("\(snapshot.totalMinutes)m")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: min(ringSize, 92), height: min(ringSize, 92))

            Text(snapshot.isGoalMet ? "Day won" : "Daily Poms")
                .font(.caption.bold())
                .foregroundStyle(snapshot.isGoalMet ? Color.green : Color.primary)

            if snapshot.streak > 0 {
                Label("\(snapshot.streak)-day streak", systemImage: "flame.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilitySummary)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.isGoalMet ? "All done — day won" : "Today's poms")
                    .font(.headline)
                Spacer()
                Text("\(snapshot.completedCount)/\(snapshot.dailyGoal)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if snapshot.recentSessions.isEmpty {
                Spacer(minLength: 4)
                Label("Tap to start a focus chunk", systemImage: "timer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
            } else {
                ForEach(Array(snapshot.recentSessions.prefix(3).enumerated()), id: \.offset) { _, session in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(snapshot.isGoalMet ? Color.green : Color.accentColor)
                        Text(session.label)
                            .lineLimit(1)
                        Spacer()
                        Text("\(session.durationMinutes)m")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }

            HStack(spacing: 12) {
                Text("\(snapshot.totalMinutes)m focused")
                if snapshot.streak > 0 {
                    Label("\(snapshot.streak)-day streak", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

@main
struct DailyPomsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyPomsWidget", provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Poms")
        .description("Today's pom count, focused minutes, and streak.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular,
        ])
    }
}
