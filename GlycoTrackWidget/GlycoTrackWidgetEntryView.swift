import SwiftUI
import WidgetKit

struct GlycoTrackWidgetEntryView: View {
    let entry: GlycoTrackWidgetEntry

    var body: some View {
        VStack(spacing: 8) {
            // Tap the link to open recording
            Link(destination: URL(string: "glycotrack://record")!) {
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
