import WidgetKit
import SwiftUI

struct GlycoTrackWidgetEntry: TimelineEntry {
    let date: Date
    let todayGL: Double
    let entryCount: Int
}

struct GlycoTrackWidgetProvider: TimelineProvider {
    private let sharedDefaults = UserDefaults(suiteName: "group.com.glycotrack.shared")

    func placeholder(in context: Context) -> GlycoTrackWidgetEntry {
        GlycoTrackWidgetEntry(date: Date(), todayGL: 45.0, entryCount: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlycoTrackWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlycoTrackWidgetEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func currentEntry() -> GlycoTrackWidgetEntry {
        let gl = sharedDefaults?.double(forKey: "todayGL") ?? 0.0
        let count = sharedDefaults?.integer(forKey: "todayEntryCount") ?? 0
        return GlycoTrackWidgetEntry(date: Date(), todayGL: gl, entryCount: count)
    }
}

@main
struct GlycoTrackWidget: Widget {
    let kind = "GlycoTrackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlycoTrackWidgetProvider()) { entry in
            GlycoTrackWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("GlycoTrack")
        .description("Log food by voice and track today's GL progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
