import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeTabView()
                .tabItem {
                    Label("Today", systemImage: "house.fill")
                }

            WeekTabView()
                .tabItem {
                    Label("Week", systemImage: "calendar.badge.clock")
                }

            MonthTabView()
                .tabItem {
                    Label("Month", systemImage: "calendar")
                }

            LogTabView()
                .tabItem {
                    Label("Log", systemImage: "list.bullet")
                }

            SummaryTabView()
                .tabItem {
                    Label("Summary", systemImage: "text.magnifyingglass")
                }

            AboutTabView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }

            DebugTabView()
                .tabItem {
                    Label("Debug", systemImage: "wrench.and.screwdriver")
                }
        }
    }
}
