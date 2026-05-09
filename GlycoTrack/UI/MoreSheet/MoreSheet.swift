import SwiftUI

/// Single sheet that consolidates the previously-disparate Settings, About,
/// and Debug surfaces. Presented from the Today tab toolbar gear button.
/// A segmented control toggles between the three panes; each pane is
/// implemented in its own file (`SettingsPaneView`, `AboutPaneView`,
/// `DebugPaneView`) so they can evolve independently.
struct MoreSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var pane: Pane = .settings
    @State private var debugExportRequested: Bool = false

    enum Pane: String, CaseIterable, Identifiable {
        case settings, about, debug
        var id: String { rawValue }
        var label: String {
            switch self {
            case .settings: return "Settings"
            case .about:    return "About"
            case .debug:    return "Debug"
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Pane", selection: $pane) {
                    ForEach(Pane.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Divider().opacity(0.4)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 8) {
                    if pane == .debug {
                        Button("Export JSON") { debugExportRequested = true }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray5))
                            .cornerRadius(10)
                    }
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .settings: SettingsPaneView()
        case .about:    AboutPaneView()
        case .debug:    DebugPaneView(exportRequested: $debugExportRequested)
        }
    }
}
