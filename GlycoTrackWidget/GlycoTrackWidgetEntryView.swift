import SwiftUI
import WidgetKit

struct GlycoTrackWidgetEntryView: View {
    let entry: GlycoTrackWidgetEntry
    @Environment(\.widgetFamily) private var family

    private let recordURL = URL(string: "glycotrack://record")!

    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        case .accessoryInline:
            accessoryInline
        default:
            homescreenView
        }
    }

    // MARK: - Home screen (systemSmall / systemMedium)

    private var homescreenView: some View {
        VStack(spacing: 8) {
            // Tap the link to open recording
            Link(destination: recordURL) {
                VStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.accentColor)
                        .clipShape(Circle())

                    Text("Log Food")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }

            // Today's GL progress
            VStack(spacing: 2) {
                GLProgressBar(gl: entry.todayGL, budget: 100)
                    .frame(height: 6)
                    .padding(.horizontal, 12)

                Text("GL \(Int(entry.todayGL)) / 100")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetContainerBackground { Color(.systemBackground) }
    }

    // MARK: - Lock Screen / StandBy

    /// Compact ring with the GL number at center. Sized for the ~58pt circle
    /// the system reserves; the ring uses `widgetAccentable()` so tinted
    /// renders pick it up while the digits stay readable.
    private var accessoryCircular: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(entry.todayGL / 100.0, 1.0))
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                // Rotate so the trim starts at 12 o'clock instead of 3.
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: -1) {
                Text("\(Int(entry.todayGL))")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("GL")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(2)
        .widgetURL(recordURL)
        .widgetContainerBackground { Color.clear }
    }

    /// Two-line readout. Top: progress bar + percentage, bottom: today's
    /// entry count. The bar is the only colored chrome — the digits stay
    /// in the system foreground tint so the widget reads on any wallpaper.
    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(Int(entry.todayGL)) / 100")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }

            GLProgressBar(gl: entry.todayGL, budget: 100)
                .frame(height: 5)
                .widgetAccentable()

            Text(entry.entryCount == 1 ? "1 food logged" : "\(entry.entryCount) foods logged")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .widgetURL(recordURL)
        .widgetContainerBackground { Color.clear }
    }

    /// One-line readout for the inline accessory slot above the clock.
    /// Single line, no colors — system formats this whole string.
    private var accessoryInline: some View {
        Text("GL \(Int(entry.todayGL))/100 · \(entry.entryCount) foods")
            .widgetURL(recordURL)
            .widgetContainerBackground { Color.clear }
    }
}

private extension View {
    /// iOS 17 requires every widget root view to declare its background via
    /// `containerBackground(for: .widget)` so the system can extract / mask it
    /// for StandBy, the Lock Screen, and tinted/accented modes. Without it the
    /// widget renders as a black rectangle with the warning "Please adopt
    /// containerBackground API". This shim keeps the iOS 16 fallback path
    /// (plain `.background`) working so the deployment target doesn't have to
    /// move.
    @ViewBuilder
    func widgetContainerBackground<Background: View>(@ViewBuilder _ background: () -> Background) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) { background() }
        } else {
            self.background(background())
        }
    }
}

struct GLProgressBar: View {
    let gl: Double
    let budget: Double

    private var progress: Double {
        min(gl / budget, 1.0)
    }

    private var barColor: Color {
        if progress < 0.6 { return .green }
        if progress < 0.85 { return .orange }
        return .red
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule()
                    .fill(barColor)
                    .frame(width: geo.size.width * progress)
            }
        }
    }
}
