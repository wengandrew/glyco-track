import SwiftUI
import CoreData

struct WeekTabView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
        predicate: weekPredicate(),
        animation: .default
    )
    private var weekEntries: FetchedResults<FoodLogEntry>

    @State private var showCLView = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Weekly GL river
                    WeeklyRiverView(entries: Array(weekEntries))
                        .padding(.horizontal, 4)

                    Divider().padding(.horizontal)

                    // CL toggle
                    Toggle(isOn: $showCLView) {
                        Label("Show Cholesterol Load", systemImage: "heart.fill")
                            .font(.subheadline)
                    }
                    .padding(.horizontal)

                    if showCLView {
                        TugOfWarBarView(entries: Array(weekEntries))
                            .padding(.horizontal)
                    }

                    // Weekly stats
                    WeeklyStatsView(entries: Array(weekEntries))
                        .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("This Week")
        }
    }
}

struct WeeklyStatsView: View {
    let entries: [FoodLogEntry]

    private var totalGL: Double { entries.reduce(0) { $0 + $1.computedGL } }
    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }
    private var avgDailyGL: Double { totalGL / 7.0 }
    private var highGLCount: Int { entries.filter { $0.computedGL >= 20 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Week Summary")
                .font(.subheadline).fontWeight(.semibold)

            HStack {
                StatChip(label: "Avg Daily GL", value: String(format: "%.0f", avgDailyGL),
                         color: glGradientColor(fraction: avgDailyGL / dailyGLBudgetUI))
                StatChip(label: "Total GL", value: String(format: "%.0f", totalGL), color: .primary)
                StatChip(label: "Net CL", value: String(format: "%+.1f", netCL),
                         color: netCL < 0 ? .green : .red)
            }

            if highGLCount > 0 {
                Label("\(highGLCount) high-GL entries this week", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

private func weekPredicate() -> NSPredicate {
    let cal = Calendar.current
    let now = Date()
    let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
    let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
    return NSPredicate(format: "timestamp >= %@ AND timestamp < %@ AND isDeleted == NO",
                       start as NSDate, end as NSDate)
}
