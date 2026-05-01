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
            }
            .navigationTitle(pane.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
                if pane == .debug {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Export JSON") { debugExportRequested = true }
                    }
                }
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
