import SwiftUI
import Speech
import AVFoundation

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var requestingPermissions = false
    @State private var showDeniedAlert = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo — app icon loaded from the asset catalog
                Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .padding(.bottom, 28)

                Text("GlycoTrack")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .padding(.bottom, 8)

                Text("Just say what you ate — or what you had yesterday — and GlycoTrack handles the rest.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)

                Text("Everything stays on your device. AI-powered voice recognition categorizes your meals accurately in seconds.")
                    .font(.callout)
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
        .alert("Permissions Required", isPresented: $showDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("GlycoTrack needs microphone and speech recognition access to log meals by voice. Please enable both in Settings → Privacy & Security.")
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    private func requestPermissionsAndContinue() async {
        requestingPermissions = true
        defer { requestingPermissions = false }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }

        guard speechStatus == .authorized, micGranted else {
            showDeniedAlert = true
            return
        }

        hasCompletedOnboarding = true
    }
}
