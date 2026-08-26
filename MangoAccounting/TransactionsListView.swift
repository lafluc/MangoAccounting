// TransactionsListView.swift

import SwiftUI
import CoreData

struct TransactionsListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var categoryManager = CategoryManager.shared

    // MARK: - Sort, Filter, Search State
    @State private var searchQuery: String = ""
    @State private var selectedSortOption: SortOption = .dateDescending
    @State private var selectedFilterOption: FilterOption = .all
    @State private var selectedCategory: String = "All"
    
    // NEW: Yearly Partitioning State
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    enum SortOption: String, CaseIterable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case amountDescending = "Amount (High-Low)"
        case amountAscending = "Amount (Low-High)"
    }
    
    enum FilterOption: String, CaseIterable {
        case all = "All Types"
        case income = "Income"
        case expense = "Expense"
    }

    // Dynamic Fetch Request
    @FetchRequest private var transactions: FetchedResults<TransactionItem>

    init() {
        _transactions = FetchRequest<TransactionItem>(
            sortDescriptors: [NSSortDescriptor(keyPath: \TransactionItem.date, ascending: false)],
            animation: .default
        )
    }
    
    private var filteredTransactions: [TransactionItem] {
        if searchQuery.isEmpty {
            return Array(transactions)
        } else {
            return transactions.filter {
                $0.details?.localizedCaseInsensitiveContains(searchQuery) ?? false ||
                $0.category?.localizedCaseInsensitiveContains(searchQuery) ?? false
            }
        }
    }
    
    private var availableCategories: [String] {
        let allCats = categoryManager.incomeCategories + categoryManager.expenseCategories
        return ["All"] + Array(Set(allCats)).sorted()
    }
    
    // Calculate available years from existing data + current year
    private var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        var years = Set<Int>()
        years.insert(currentYear)
        
        // We need a separate fetch to find all years, or we just rely on what is loaded.
        // A simple heuristic for the UI: current year +/- 5 years is usually enough for a picker,
        // but let's try to be smart.
        // For simplicity in this view, we will offer a range.
        return (currentYear-5...currentYear+1).map { $0 }.sorted(by: >)
    }
    
    // Formatter to remove comma from year (2,025 -> 2025)
    private var yearFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.groupingSeparator = ""
        return formatter
    }

    @State private var showAddSheet = false
    @State private var transactionToDelete: TransactionItem?
    @State private var offsetsToDelete: IndexSet?
    @State private var showDeleteConfirmation = false
    @State private var saveErrorMessage: String?
    @State private var transactionToDuplicate: ManagedObjectBox<TransactionItem>?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Year Partition Header
                HStack {
                    Text("Fiscal Year:")
                        .font(.headline)
                        .foregroundColor(AppTheme.textSecondary)
                    
                    Menu {
                        ForEach(availableYears, id: \.self) { year in
                            Button {
                                selectedYear = year
                            } label: {
                                if selectedYear == year {
                                    Label(yearFormatter.string(from: NSNumber(value: year)) ?? "", systemImage: "checkmark")
                                } else {
                                    Text(yearFormatter.string(from: NSNumber(value: year)) ?? "")
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(yearFormatter.string(from: NSNumber(value: selectedYear)) ?? "")
                                .font(.headline)
                                .foregroundColor(AppTheme.accent)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(AppTheme.accent)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(AppTheme.background)

                listBody
            }
            .searchable(text: $searchQuery, prompt: "Search by description or category")
            .navigationTitle("Transactions")
            .toolbar { mainToolbar }
            .sheet(isPresented: $showAddSheet) {
                NavigationStack {
                    AddTransactionView()
                }
                // A macOS sheet is sized from the fitting size of its root, and a
                // NavigationView/Stack does not forward its child's minimums. The
                // frame has to be here, not inside AddTransactionView.
                .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 680)
            }
            .sheet(item: $transactionToDuplicate) { source in
                NavigationStack {
                    AddTransactionView(prefillSource: source.object)
                }
                .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 680)
            }
        }
        .onChange(of: selectedSortOption) { updateFetchRequest() }
        .onChange(of: selectedFilterOption) { updateFetchRequest() }
        .onChange(of: selectedCategory) { updateFetchRequest() }
        // Update fetch request when year changes
        .onChange(of: selectedYear) { updateFetchRequest() }
        .onAppear { updateFetchRequest() } // Ensure correct filter on load
        .alert("Are you sure?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let transaction = transactionToDelete {
                    delete(transaction: transaction)
                } else if let offsets = offsetsToDelete {
                    deleteItems(at: offsets)
                }
            }
            Button("Cancel", role: .cancel) {
                transactionToDelete = nil
                offsetsToDelete = nil
            }
        } message: {
            Text("This transaction will be permanently deleted.")
        }
        .alert(
            "Could Not Save",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 620)
        #endif
    }

    @ViewBuilder
    private var listBody: some View {
        if transactions.isEmpty && searchQuery.isEmpty {
            PlaceholderView(
                systemImageName: "tray.fill",
                title: "No Transactions Yet",
                subtitle: "Tap the ‘+’ button to add your first income or expense entry for this year."
            )
        } else {
            List {
                ForEach(filteredTransactions, id: \.objectID) { transaction in
                    NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                        TransactionRowView(transaction: transaction)
                    }
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        Button {
                            transactionToDuplicate = ManagedObjectBox(transaction)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Divider()
                        Button(role: .destructive) {
                            confirmDelete(transaction: transaction)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: confirmDelete)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .overlay {
                if filteredTransactions.isEmpty && !searchQuery.isEmpty {
                    ContentUnavailableView.search
                }
            }
        }
    }
    
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Sort", selection: $selectedSortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                Divider()
                Picker("Filter by Type", selection: $selectedFilterOption) {
                    ForEach(FilterOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                Picker("Filter by Category", selection: $selectedCategory) {
                    ForEach(availableCategories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
            } label: {
                Label("Sort & Filter", systemImage: "arrow.up.arrow.down.circle")
            }
            .tint(AppTheme.accent)
            
            Button { showAddSheet = true } label: { Label("Add", systemImage: "plus.circle.fill") }
            .tint(AppTheme.accent)
        }
    }
    
    // MARK: - Core Data Functions
    private func updateFetchRequest() {
        let sortDescriptors: [NSSortDescriptor]
        switch selectedSortOption {
            case .dateDescending:
                sortDescriptors = [NSSortDescriptor(keyPath: \TransactionItem.date, ascending: false)]
            case .dateAscending:
                sortDescriptors = [NSSortDescriptor(keyPath: \TransactionItem.date, ascending: true)]
            case .amountDescending:
                sortDescriptors = [NSSortDescriptor(keyPath: \TransactionItem.amount, ascending: false)]
            case .amountAscending:
                sortDescriptors = [NSSortDescriptor(keyPath: \TransactionItem.amount, ascending: true)]
        }
        
        var predicates: [NSPredicate] = []
        
        // Date Filter for selected Year
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = selectedYear
        components.day = 1
        components.month = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        
        if let startDate = calendar.date(from: components),
           let endDate = calendar.date(byAdding: .year, value: 1, to: startDate) {
            predicates.append(NSPredicate(format: "date >= %@ AND date < %@", startDate as NSDate, endDate as NSDate))
        }

        switch selectedFilterOption {
            case .income:
                predicates.append(NSPredicate(format: "type == %@", "Income"))
            case .expense:
                predicates.append(NSPredicate(format: "type == %@", "Expense"))
            case .all:
                break
        }
        if selectedCategory != "All" {
            predicates.append(NSPredicate(format: "category == %@", selectedCategory))
        }
        
        let compoundPredicate = predicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        transactions.nsSortDescriptors = sortDescriptors
        transactions.nsPredicate = compoundPredicate
    }

    private func confirmDelete(transaction: TransactionItem) {
        self.transactionToDelete = transaction
        self.showDeleteConfirmation = true
    }

    private func confirmDelete(at offsets: IndexSet) {
        if let index = offsets.first {
            self.transactionToDelete = filteredTransactions[index]
            self.showDeleteConfirmation = true
        }
    }

    private func delete(transaction: TransactionItem) {
        withAnimation {
            viewContext.delete(transaction)
            saveContext()
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        withAnimation {
            let itemsToDelete = offsets.map { filteredTransactions[$0] }
            itemsToDelete.forEach(viewContext.delete)
            saveContext()
        }
    }
    
    private func saveContext() {
        if let message = viewContext.saveOrRollback() {
            saveErrorMessage = message
        }
    }
}
