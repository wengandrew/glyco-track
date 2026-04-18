import SwiftUI

struct SummaryTabView: View {
    @StateObject private var generator: SummaryGenerator

    init() {
        let apiKey = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String ?? ""
        _generator = StateObject(wrappedValue: SummaryGenerator(
            apiKey: apiKey,
            logRepository: FoodLogRepository()
        ))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if generator.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.3)
                            Text("Generating your summary…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else if generator.summary.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No summary yet")
                                .font(.headline)
                            Text("Log at least a few meals and tap 'Update me' to get started.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        Text(generator.summary)
                            .font(.body)
                            .lineSpacing(4)
                            .padding(.horizontal)

                        if let date = generator.lastGeneratedAt {
                            Text("Last updated \(date, style: .relative) ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                    }

                    Button {
                        Task { await generator.generate() }
                    } label: {
                        Label("Update me", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(generator.isLoading)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.bottom, 20)
                .padding(.top, 16)
            }
            .navigationTitle("Summary")
        }
        .task {
            await generator.generateIfNeeded()
        }
    }
}
