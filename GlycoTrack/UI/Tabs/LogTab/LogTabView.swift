import SwiftUI
import CoreData

struct LogTabView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
        predicate: NSPredicate(format: "isSoftDeleted == NO"),
        animation: .default
    )
    private var entries: FetchedResults<FoodLogEntry>

    @State private var selectedEntry: FoodLogEntry?
    @State private var showManualEntry = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var filteredEntries: [FoodLogEntry] {
        guard !searchText.isEmpty else { return Array(entries) }
        return entries.filter { $0.foodDescription.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                List {
                    ForEach(filteredEntries) { entry in
                        FoodLogRowView(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedEntry = entry }
                            .listRowBackground(theme.pageBackground)
                    }
                    .onDelete(perform: softDelete)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(theme.pageBackground)
            }
            .background(theme.pageBackground)
            .navigationTitle("Food Log")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showManualEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedEntry) { entry in
                FoodEntryDetailSheet(entry: entry)
            }
            .sheet(isPresented: $showManualEntry) {
                ManualEntryView()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 15))
                TextField("Search foods", text: $searchText)
                    .font(.system(.body, design: theme.fontDesign))
                    .focused($searchFocused)
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray5).opacity(0.8))
            .cornerRadius(12)

            if searchFocused {
                Button("Cancel") {
                    searchText = ""
                    searchFocused = false
                }
                .font(.system(.body, design: theme.fontDesign))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: searchFocused)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.pageBackground)
    }

    private func softDelete(at offsets: IndexSet) {
        let repo = FoodLogRepository(context: context)
        let displayed = filteredEntries
        offsets.forEach { repo.softDelete(displayed[$0]) }
    }
}

