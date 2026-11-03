import SwiftUI
import SwiftData

@main
struct DailyPomsApp: App {
    private enum LoadState {
        case loading
        case loaded(ModelContainer)
        case failed(String)
    }

    @State private var loadState: LoadState = .loading
    @State private var showResetConfirmation = false

    init() {
        UserDefaults.standard.register(defaults: [
            SharedConstants.dailyGoalKey: SharedConstants.defaultDailyGoal,
            "focusDurationMinutes": 25,
            "shortBreakMinutes": 5,
            "longBreakMinutes": 15,
            "keepScreenAwake": true,
            "timerCompletionAlertEnabled": true,
            "morningReminderMinutes": 9 * 60,
            "eveningReminderMinutes": 20 * 60,
        ])
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch loadState {
                case .loading:
                    LoadingView()
                case .loaded(let container):
                    ContentView()
                        .modelContainer(container)
                case .failed(let message):
                    storeErrorView(message: message)
                }
            }
            .task {
                await load()
            }
        }
    }

    private func load() async {
        if case .loaded = loadState { return }
        loadState = .loading
        do {
            loadState = .loaded(try await ContainerLoader.shared.load())
        } catch {
            AppLog.app.error("Store load failed: \(String(describing: error), privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    private func storeErrorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't open your data", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Daily Poms couldn't open its on-device store. Your data file has not been changed. You can try again, or reset and start fresh.\n\n\(message)")
        } actions: {
            VStack(spacing: 10) {
                Button("Try Again") {
                    Task { await load() }
                }
                .buttonStyle(.borderedProminent)

                Button("Reset Data and Start Fresh", role: .destructive) {
                    showResetConfirmation = true
                }
                .buttonStyle(.bordered)
            }
        }
        .confirmationDialog(
            "Delete all Daily Poms data?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                Task {
                    await Task.detached(priority: .userInitiated) {
                        SharedStore.deleteStoreFiles()
                    }.value
                    await ContainerLoader.shared.reset()
                    await load()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your focus chunks, history, and streaks on this iPhone. This cannot be undone.")
        }
    }
}

/// Brief branded loading state while the store opens off-main-thread.
private struct LoadingView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.system(size: iconSize))
                .foregroundStyle(Color.accentColor)
            ProgressView()
            Text("Daily Poms")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Daily Poms")
    }
}
