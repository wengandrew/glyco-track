import SwiftUI
import Speech
import AVFoundation

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var requestingPermissions = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.accentColor)
                }
                .padding(.bottom, 28)

                Text("GlycoTrack")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .padding(.bottom, 8)

                Text("Voice-first food logging.\nTwo numbers. One honest picture.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 48)

                // Permission cards
                VStack(spacing: 12) {
                    permissionCard(
                        icon: "mic.fill",
                        color: .blue,
                        title: "Microphone",
                        detail: "To capture your voice when you log a meal."
                    )
                    permissionCard(
                        icon: "waveform",
                        color: .purple,
                        title: "Speech Recognition",
                        detail: "To transcribe speech on-device. Audio is never stored."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                Text("Not medical advice. Talk to your doctor about specific targets for you.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)

                Spacer()

                Button {
                    Task { await requestPermissionsAndContinue() }
                } label: {
                    Group {
                        if requestingPermissions {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Get Started")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .disabled(requestingPermissions)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    private func permissionCard(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func requestPermissionsAndContinue() async {
        requestingPermissions = true

        // Speech recognition (also implicitly covers mic on many iOS versions).
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { _ in
                continuation.resume()
            }
        }

        // Explicit mic permission so iOS shows its own dialog if not already granted.
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { _ in
                continuation.resume()
            }
        }

        hasCompletedOnboarding = true
    }
}
