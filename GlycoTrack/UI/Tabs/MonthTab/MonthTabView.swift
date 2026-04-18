import SwiftUI
import CoreData

struct MonthTabView: View {
    @Environment(\.managedObjectContext) private var context

    @State private var displayedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    )!

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
        predicate: NSPredicate(format: "isDeleted == NO"),
        animation: .default
    )
    private var allEntries: FetchedResults<FoodLogEntry>

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Month navigation
                    HStack {
                        Button {
                            displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth)!
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        Text(displayedMonth, format: .dateTime.month(.wide).year())
                            .font(.headline)
                        Spacer()
                        Button {
                            displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth)!
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(isCurrentMonth)
                    }
                    .padding(.horizontal)

                    MonthlyHeatmapView(month: displayedMonth) { date in
                        entries(for: date)
                    }
                    .padding(.horizontal, 4)

                    // Monthly stats
                    MonthlyStatsView(entries: monthEntries)
                        .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Month")
        }
    }

    private var isCurrentMonth: Bool {
        let cal = Calendar.current
        return cal.component(.month, from: displayedMonth) == cal.component(.month, from: Date())
            && cal.component(.year, from: displayedMonth) == cal.component(.year, from: Date())
    }

    private var monthEntries: [FoodLogEntry] {
        let cal = Calendar.current
        return allEntries.filter {
            cal.component(.month, from: $0.timestamp) == cal.component(.month, from: displayedMonth)
            && cal.component(.year, from: $0.timestamp) == cal.component(.year, from: displayedMonth)
        }
    }

    private func entries(for date: Date) -> [FoodLogEntry] {
        let cal = Calendar.current
        return allEntries.filter { cal.isDate($0.timestamp, inSameDayAs: date) }
    }
}

struct MonthlyStatsView: View {
    let entries: [FoodLogEntry]

    private var daysLogged: Int {
        Set(entries.map { Calendar.current.startOfDay(for: $0.timestamp) }).count
    }
    private var totalGL: Double { entries.reduce(0) { $0 + $1.computedGL } }
    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }
    private var avgDailyGL: Double { daysLogged > 0 ? totalGL / Double(daysLogged) : 0 }
    private var lowConfidenceCount: Int { entries.filter { $0.confidenceScore < 0.7 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Month Summary")
                .font(.subheadline).fontWeight(.semibold)

            HStack {
                StatChip(label: "Days Logged", value: "\(daysLogged)", color: .accentColor)
                StatChip(label: "Avg Daily GL", value: String(format: "%.0f", avgDailyGL),
                         color: glGradientColor(fraction: avgDailyGL / dailyGLBudgetUI))
                StatChip(label: "Net CL", value: String(format: "%+.1f", netCL),
                         color: netCL < 0 ? .green : .red)
            }

            if lowConfidenceCount > 0 {
                Label("\(lowConfidenceCount) entries need review (low confidence)",
                      systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
