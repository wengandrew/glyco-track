import SwiftUI
import CoreData

struct HomeTabView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var voiceCapture = VoiceCapture()
    @StateObject private var logProcessor: FoodLogProcessor

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
        predicate: todayPredicate(),
        animation: .default
    )
    private var todayEntries: FetchedResults<FoodLogEntry>

    @State private var showRecordingSheet = false
    @State private var selectedVisualization = 0
    @State private var showQuadrant = false

    init() {
        _logProcessor = StateObject(wrappedValue: FoodLogProcessor())
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Record button
                    VStack(spacing: 8) {
                        RecordButton(isRecording: voiceCapture.isRecording) {
                            Task { await toggleRecording() }
                        }

                        if voiceCapture.isRecording {
                            Text("Listening...")
                                .font(.caption)
                                .foregroundColor(.red)
                                .animation(.easeInOut, value: voiceCapture.isRecording)
                        } else {
                            Text("Tap to log food by voice")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if voiceCapture.isRecording || !voiceCapture.transcript.isEmpty {
                            Text(voiceCapture.transcript)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 8)

                    // Processing indicator
                    if logProcessor.isProcessing {
                        HStack {
                            ProgressView()
                            Text("Processing your food log…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if logProcessor.lastError != nil {
                        Text("Could not process: \(logProcessor.lastError!)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    // GL Visualization picker
                    Picker("GL View", selection: $selectedVisualization) {
                        Text("Daily Bucket").tag(0)
                        Text("Tug of War").tag(1)
                        Text("Waterline").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    let entries = Array(todayEntries)

                    switch selectedVisualization {
                    case 0:
                        DailyBucketView(entries: entries)
                            .padding(.horizontal)
                    case 1:
                        TugOfWarBarView(entries: entries)
                            .padding(.horizontal)
                    default:
                        WaterlineView(entries: entries)
                            .padding(.horizontal)
                    }

                    // Quadrant link
                    Button {
                        showQuadrant = true
                    } label: {
                        HStack {
                            Image(systemName: "chart.scatter")
                            Text("View GL × CL Quadrant")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    // Today's log summary
                    if !entries.isEmpty {
                        TodayEntrySummary(entries: entries)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Today")
            .sheet(isPresented: $showQuadrant) {
                NavigationView {
                    QuadrantPlotView(entries: Array(todayEntries))
                        .navigationTitle("GL × CL Quadrant")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showQuadrant = false }
                            }
                        }
                }
            }
        }
        .onOpenURL { url in
            if url.scheme == "glycotrack" && url.host == "record" {
                Task { await toggleRecording() }
            }
        }
    }

    private func toggleRecording() async {
        if voiceCapture.isRecording {
            voiceCapture.stopRecording()
        } else {
            voiceCapture.onTranscriptFinalized = { transcript in
                Task {
                    await logProcessor.process(transcript: transcript, context: context)
                    updateWidgetData()
                }
            }
            do {
                try await voiceCapture.startRecording()
            } catch {
                // Error shown via voiceCapture.error
            }
        }
    }

    private func updateWidgetData() {
        let defaults = UserDefaults(suiteName: "group.com.glycotrack.shared")
        let repo = FoodLogRepository(context: context)
        defaults?.set(repo.dailyGL(for: Date()), forKey: "todayGL")
        defaults?.set(repo.countToday(), forKey: "todayEntryCount")
    }
}

struct TodayEntrySummary: View {
    let entries: [FoodLogEntry]

    private var totalGL: Double { entries.reduce(0) { $0 + $1.computedGL } }
    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                StatChip(label: "Total GL", value: String(format: "%.1f", totalGL),
                         color: glGradientColor(fraction: totalGL / dailyGLBudgetUI))
                StatChip(label: "Net CL", value: String(format: "%+.2f", netCL),
                         color: netCL < 0 ? .green : .red)
                StatChip(label: "Foods", value: "\(entries.count)", color: .accentColor)
            }
        }
    }
}

struct StatChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

private func todayPredicate() -> NSPredicate {
    let start = Calendar.current.startOfDay(for: Date())
    let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
    return NSPredicate(format: "timestamp >= %@ AND timestamp < %@ AND isDeleted == NO",
                       start as NSDate, end as NSDate)
}
