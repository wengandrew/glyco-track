import SwiftUI

/// Smaller variant of `RecordButton` sized for the floating tab bar.
struct CompactRecordButton: View {
    let isRecording: Bool
    let theme: AppTheme
    let action: () -> Void

    @State private var pulse: Bool = false

    private var activeColor: Color { isRecording ? Color.red : theme.recordButtonColor }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .frame(width: 60, height: 60)
                        .scaleEffect(pulse ? 1.25 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                }

                Circle()
                    .fill(activeColor)
                    .frame(width: 48, height: 48)

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { recording in
            pulse = recording
        }
    }
}
