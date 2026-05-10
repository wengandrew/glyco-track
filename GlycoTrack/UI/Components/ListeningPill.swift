import SwiftUI

/// Floating status pill that sits directly above the tab bar (next to the
/// mic button) while a recording is in progress, the transcript is being
/// processed, or processing has failed. Replaces the old in-flow recording
/// section on the Today tab — page content no longer reflows when the user
/// taps the mic.
struct ListeningPill: View {
    @ObservedObject var voiceCapture: VoiceCapture
    @ObservedObject var logProcessor: FoodLogProcessor
    let retryAction: () async -> Void

    @State private var dotPulse: Bool = false
    @State private var errorDismissTask: Task<Void, Never>? = nil

    private var isVisible: Bool {
        voiceCapture.isRecording
            || logProcessor.isProcessing
            || logProcessor.lastError != nil
    }

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 10) {
                    indicator
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundColor(headlineColor)
                        if !subline.isEmpty {
                            Text(subline)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    if logProcessor.isNetworkError
                        && logProcessor.lastError != nil
                        && !logProcessor.isProcessing
                        && !voiceCapture.isRecording {
                        retryButton
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear { dotPulse = true }
                .onDisappear {
                    dotPulse = false
                    errorDismissTask?.cancel()
                    errorDismissTask = nil
                }
                .onTapGesture {
                    guard !logProcessor.isNetworkError else { return }
                    if logProcessor.lastError != nil {
                        errorDismissTask?.cancel()
                        errorDismissTask = nil
                        logProcessor.lastError = nil
                    }
                }
                .onChange(of: logProcessor.lastError) { newError in
                    errorDismissTask?.cancel()
                    errorDismissTask = nil
                    // Don't auto-dismiss network errors — the retry button keeps it visible.
                    if newError != nil && !logProcessor.isNetworkError {
                        errorDismissTask = Task { @MainActor in
                            try? await Task.sleep(for: .seconds(4))
                            if !Task.isCancelled {
                                logProcessor.lastError = nil
                            }
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isVisible)
    }

    private var retryButton: some View {
        Button {
            Task { await retryAction() }
        } label: {
            Text("Retry")
                .font(.system(.caption, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var indicator: some View {
        if voiceCapture.isRecording {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .scaleEffect(dotPulse ? 1.0 : 0.7)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: dotPulse)
        } else if logProcessor.isProcessing {
            ProgressView()
                .controlSize(.small)
        } else if logProcessor.lastError != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }

    private var headline: String {
        if voiceCapture.isRecording { return "Listening…" }
        if logProcessor.isProcessing { return "Processing…" }
        if logProcessor.lastError != nil { return "Couldn't log that" }
        return ""
    }

    private var headlineColor: Color {
        if logProcessor.lastError != nil { return .orange }
        return .primary
    }

    private var subline: String {
        if voiceCapture.isRecording {
            return voiceCapture.transcript.isEmpty ? "Tap stop or pause briefly." : voiceCapture.transcript
        }
        if logProcessor.isProcessing {
            return voiceCapture.transcript
        }
        if let err = logProcessor.lastError {
            return err
        }
        return ""
    }
}
