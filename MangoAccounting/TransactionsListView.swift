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
    @State private var selectedYear: Int = FiscalCalendar.year(of: Date())

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
        // Predicated from the start. Built unfiltered before, so the first frame
        // rendered every transaction of every year and then animated them away.
        let bounds = FiscalCalendar.yearBounds(FiscalCalendar.year(of: Date()))
        _transactions = FetchRequest<TransactionItem>(
            sortDescriptors: [NSSortDescriptor(keyPath: \TransactionItem.date, ascending: false)],
            predicate: NSPredicate(
                format: "date >= %@ AND date < %@", bounds.start as NSDate, bounds.end as NSDate
            ),
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
    
    /// True when the list is empty because of the current year, type or category
    /// selection rather than because the ledger holds nothing at all.
    private var isEmptyDueToSelection: Bool {
        !allTransactionYears.isEmpty
            || selectedFilterOption != .all
            || selectedCategory != "All"
    }

    private var availableCategories: [String] {
        let allCats = categoryManager.incomeCategories + categoryManager.expenseCategories
        return ["All"] + Array(Set(allCats)).sorted()
    }
    
    /// Years the user can switch to: every year that actually holds data, plus the
    /// current one and whatever is selected.
    ///
    /// This used to hardcode `currentYear-5 ... currentYear+1`, which made older
    /// transactions unreachable from this tab entirely.
    private var availableYears: [Int] {
        var years = Set(allTransactionYears)
        years.insert(FiscalCalendar.year(of: Date()))
        years.insert(selectedYear)
        return years.sorted(by: >)
    }

    @State private var showAddSheet = false
    /// Rows awaiting delete confirmation. Replaces a `TransactionItem?` plus an
    /// `IndexSet?` that was never assigned, which made a multi-row delete drop
    /// everything but the first row.
    @State private var transactionsToDelete: [TransactionItem]?
    @State private var saveErrorMessage: String?
    @State private var transactionToDuplicate: ManagedObjectBox<TransactionItem>?
    /// Years the ledger spans, loaded once so the picker is not limited to a
    /// hardcoded window around today.
    @State private var allTransactionYears: [Int] = []

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
                                    Label(FiscalCalendar.yearText(year), systemImage: "checkmark")
                                } else {
                                    Text(FiscalCalendar.yearText(year))
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(FiscalCalendar.yearText(selectedYear))
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
        .onAppear {
            updateFetchRequest()
            allTransactionYears = TransactionYears.spanned(in: viewContext)
        }
        .alert(
            "Are you sure?",
            isPresented: Binding(
                get: { transactionsToDelete != nil },
                set: { if !$0 { transactionsToDelete = nil } }
            ),
            presenting: transactionsToDelete
        ) { targets in
            Button("Delete", role: .destructive) { delete(targets) }
            Button("Cancel", role: .cancel) { transactionsToDelete = nil }
        } message: { targets in
            Text(targets.count == 1
                 ? "This transaction will be permanently deleted."
                 : "These \(targets.count) transactions will be permanently deleted.")
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
            if isEmptyDueToSelection {
                PlaceholderView(
                    systemImageName: "line.3.horizontal.decrease.circle",
                    title: "Nothing Matches These Filters",
                    subtitle: "No transactions in this year, type or category. Try a different fiscal year or clear the filters."
                )
            } else {
                PlaceholderView(
                    systemImageName: "tray.fill",
                    title: "No Transactions Yet",
                    subtitle: "Use the ‘+’ button to add your first income or expense entry for this year."
                )
            }
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
                        Text(LocalizedStringKey(option.rawValue)).tag(option)
                    }
                }
                Divider()
                Picker("Filter by Type", selection: $selectedFilterOption) {
                    ForEach(FilterOption.allCases, id: \.self) { option in
                        Text(LocalizedStringKey(option.rawValue)).tag(option)
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
        
        // Date filter for the selected year, against a fixed calendar so the
        // boundary does not move with the device's time zone.
        let bounds = FiscalCalendar.yearBounds(selectedYear)
        predicates.append(NSPredicate(
            format: "date >= %@ AND date < %@", bounds.start as NSDate, bounds.end as NSDate
        ))

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
        self.transactionsToDelete = [transaction]
    }

    private func confirmDelete(at offsets: IndexSet) {
        // Resolve to objects now: the confirmation is asynchronous, and indices
        // into a recomputed array can point at different rows by the time it is
        // answered — or out of bounds if the array shrank.
        let rows = filteredTransactions
        let targets = offsets.compactMap { $0 < rows.count ? rows[$0] : nil }
        guard !targets.isEmpty else { return }
        self.transactionsToDelete = targets
    }

    private func delete(_ targets: [TransactionItem]) {
        withAnimation {
            for target in targets where !target.isDeleted {
                viewContext.delete(target)
            }
            saveContext()
        }
        transactionsToDelete = nil
    }
    
    private func saveContext() {
        if let message = viewContext.saveOrRollback() {
            saveErrorMessage = message
        }
    }
}
