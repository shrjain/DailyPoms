import SwiftUI

/// The three top-level screens, in swipe order.
enum AppTab: Int, CaseIterable, Identifiable {
    case today
    case history
    case settings

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "timer"
        case .history: "calendar"
        case .settings: "gearshape"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .today: "tab.today"
        case .history: "tab.history"
        case .settings: "tab.settings"
        }
    }

    /// Launch-argument override used only for App Store screenshots
    /// in Debug builds: `-initialTab history`.
    static var initial: AppTab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-initialTab"), args.indices.contains(index + 1) {
            switch args[index + 1] {
            case "history": return .history
            case "settings": return .settings
            default: return .today
            }
        }
        #endif
        return .today
    }
}

/// Root view. Pages swipe horizontally; a custom tab bar mirrors the
/// selection so tabs stay tappable.
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: AppTab = AppTab.initial
    @ScaledMetric(relativeTo: .body) private var tabIconSize: CGFloat = 21

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tag(AppTab.today)

            HistoryView()
                .tag(AppTab.history)

            SettingsView()
                .tag(AppTab.settings)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: tabIconSize,
                                          weight: selection == tab ? .semibold : .regular))
                            .frame(height: 26)
                            .padding(.horizontal, 14)
                            .background {
                                if selection == tab {
                                    Capsule().fill(Color.accentColor.opacity(0.15))
                                }
                            }
                        Text(tab.title)
                            .font(.caption2)
                            .fontWeight(selection == tab ? .semibold : .regular)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
                    .padding(.bottom, 2)
                    .contentShape(Rectangle())
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.title))
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 0.5)
                }
        }
    }

    private func select(_ tab: AppTab) {
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { selection = tab }
        } else {
            selection = tab
        }
    }
}

#Preview {
    ContentView()
}

