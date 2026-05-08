import SwiftUI
import Speech
import AVFoundation

/// Shown as a fullScreenCover on first launch. Explains the app, surfaces the
/// mic/speech permission rationale before the system dialogs appear, and
/// collects both authorizations before dismissing.
struct OnboardingView: View {
    @AppStorage(AppSettings.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @State private var isRequesting = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    featuresSection
                    permissionsSection
                    disclaimerSection
                    Spacer(minLength: 24)
                    getStartedButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GlycoTrack")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Voice-first food logging that tracks glycemic load and cholesterol load — two independent measures of metabolic and heart risk.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            featureRow(
                icon: "mic.fill",
                title: "Speak your meals",
                detail: "Say what you ate — the app parses ingredients and quantities from natural speech."
            )
            featureRow(
                icon: "drop.fill",
                title: "Glycemic Load",
                detail: "Tracks how much each meal is likely to raise blood sugar. Daily budget: 100."
            )
            featureRow(
                icon: "heart.fill",
                title: "Cholesterol Load",
                detail: "Tracks net LDL impact — harmful fats raise it, fiber and unsaturated fats lower it."
            )
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Text("GlycoTrack needs two permissions to work:")
                .font(.callout)
                .foregroundColor(.secondary)
            permissionRow(
                icon: "mic.circle.fill",
                title: "Microphone",
                detail: "To record your voice while you describe a meal."
            )
            permissionRow(
                icon: "waveform",
                title: "Speech Recognition",
                detail: "To convert your recording to text on-device before it's processed."
            )
            Text("Both are used only while you're actively recording. No audio is stored.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var disclaimerSection: some View {
        Text("GlycoTrack is for informational purposes only and is not a substitute for professional medical advice, diagnosis, or treatment. Always consult your physician before making dietary changes.")
            .font(.footnote)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var getStartedButton: some View {
        Button {
            guard !isRequesting else { return }
            isRequesting = true
            Task {
                // Speech recognition and microphone are two separate permissions.
                await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
                }
                await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { _ in
                        continuation.resume()
                    }
                }
                hasCompletedOnboarding = true
            }
        } label: {
            Group {
                if isRequesting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text("Get Started")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isRequesting)
    }

    // MARK: - Reusable rows

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
