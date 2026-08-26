// AddTransactionView.swift

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AddTransactionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var categoryManager = CategoryManager.shared
    @StateObject private var userSettings = UserSettings() // To access currency list
    
    var transactionToEdit: TransactionItem?
    /// When set, the form opens as a *new* transaction prefilled from this one.
    /// Used by the Duplicate action; the source object is never modified.
    var prefillSource: TransactionItem?
    @State private var type: String = "Expense"
    @State private var details: String = ""
    @State private var date: Date = .now
    @State private var category: String = ""
    
    // MARK: - Currency State
    @State private var selectedCurrency: String = "CHF"
    @State private var isCustomCurrency: Bool = false
    @State private var customCurrencyCode: String = ""
    @State private var originalAmountInput: Double? // Amount in selected currency
    @State private var exchangeRate: Double = 1.0
    
    // This is the calculated base amount (CHF)
    private var baseAmountCHF: Double? {
        guard let original = originalAmountInput else { return nil }
        if selectedCurrency == "CHF" {
            return original
        } else {
            return original * exchangeRate
        }
    }
    
    @State private var carKilometers: Double?
    @State private var showCategorySheet = false
    @State private var saveErrorMessage: String?
    @State private var hasLoadedTransaction = false
    /// The rate implied by the stored amounts, kept so an untouched edit re-saves
    /// the original CHF figure instead of one recomputed from a displayed rate.
    @State private var storedExchangeRate: Double = 1.0
    /// Held while stored values are written into the form, so the type picker's
    /// onChange does not clear the category being restored.
    @State private var isApplyingStoredValues = false

    // MARK: - Title Suggestions
    @State private var allTitleSuggestions: [TitleSuggestion] = []
    @FocusState private var isDescriptionFocused: Bool

    private var titleSuggestions: [TitleSuggestion] {
        TitleSuggestionStore.rank(allTitleSuggestions, matching: details)
    }

    // MARK: - Attachment State
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var attachmentData: Data?
    @State private var attachmentType: String?
    @State private var attachmentFilename: String?
    
    private let types = ["Expense", "Income"]
    
    private var navigationTitle: String {
        transactionToEdit == nil ? "New Transaction" : "Edit Transaction"
    }

    /// Suggestions are only offered while composing; an edit already has a title.
    private var showsSuggestions: Bool { transactionToEdit == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Type", selection: $type) {
                    ForEach(types, id: \.self) { Text(LocalizedStringKey($0)) }
                }
                .pickerStyle(.segmented)

                detailsSection

                if category == ReportGenerator.carExpensesCategory {
                    carExpensesSection
                }

                attachmentSection
            }
            .padding(.horizontal)
            .padding(.top)
        }
        // A safe-area inset is laid out outside the scrolling content, so the
        // action bar keeps its height no matter how little room the sheet gets.
        // Previously Save was a sibling of an unbounded ScrollView, so a short
        // sheet clipped it away entirely and only the toolbar's Cancel survived.
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(Text(LocalizedStringKey(navigationTitle)))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            // Save also lives in the toolbar, which cannot be clipped at any
            // window size, so the primary action is always reachable.
            ToolbarItem(placement: .confirmationAction) {
                Button(saveButtonTitle) { saveTransaction() }
                    .disabled(!canSave)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .sheet(isPresented: $showCategorySheet) {
            CategoryManagementSheet()
        }
        .task(id: selectedPhotoItem) {
            guard let item = selectedPhotoItem else { return }
            if let data = try? await item.loadTransferable(type: Data.self) {
                self.attachmentData = data
                self.attachmentType = "image"
                self.attachmentFilename = "photo.jpg"
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType.pdf]
        ) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    attachmentData = try Data(contentsOf: url)
                    attachmentType = "pdf"
                    attachmentFilename = url.lastPathComponent
                } catch {
                    print("Error reading PDF data: \(error.localizedDescription)")
                }
            case .failure(let error):
                print("Error picking file: \(error.localizedDescription)")
            }
        }
        .onChange(of: type) {
            // The two types offer different categories. Keeping a stale one left
            // the picker blank while still saving the mismatched value, which then
            // landed on the wrong side of the annual report.
            guard !isApplyingStoredValues else { return }
            let allowed = type == "Income"
                ? categoryManager.incomeCategories
                : categoryManager.expenseCategories
            if !allowed.contains(category) { category = "" }
        }
        .task {
            loadTransactionDataOnce()
            allTitleSuggestions = TitleSuggestionStore.loadAll(in: viewContext)
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
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button(saveButtonTitle) { saveTransaction() }
                .buttonStyle(PillButtonStyle())
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
                .padding(.horizontal)
                .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private var saveButtonTitle: LocalizedStringKey {
        transactionToEdit == nil ? "Save" : "Update"
    }

    private var canSave: Bool {
        !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && originalAmountInput != nil
            && hasUsableCurrency
            && !category.isEmpty
    }

    /// "OTHER" is the picker's sentinel for "let me type a code", not a currency.
    /// It could previously be saved as one, and `addCurrency` then put it in the
    /// shared list permanently.
    private var hasUsableCurrency: Bool {
        !isCustomCurrency && !selectedCurrency.isEmpty && selectedCurrency != "OTHER"
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details").font(AppTheme.headlineFont).foregroundColor(AppTheme.textSecondary)
            CardView {
              VStack {
                TextField("Description (e.g., Lunch with client)", text: $details)
                    .textFieldStyle(.roundedBorder)
                    .focused($isDescriptionFocused)
                    .submitLabel(.done)

                if showsSuggestions, !titleSuggestions.isEmpty {
                    TitleSuggestionRow(suggestions: titleSuggestions) { suggestion in
                        apply(suggestion)
                    }
                }
                Divider()
                
                // MARK: - Currency Selection
                HStack {
                    Text("Currency")
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    
                    if isCustomCurrency {
                        TextField("Code", text: $customCurrencyCode)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                        Button("OK") {
                            if !customCurrencyCode.isEmpty {
                                let code = customCurrencyCode.uppercased()
                                userSettings.addCurrency(code)
                                selectedCurrency = code
                                isCustomCurrency = false
                            }
                        }
                    } else {
                        Picker("Currency", selection: $selectedCurrency) {
                            ForEach(userSettings.usedCurrencies, id: \.self) { currency in
                                Text(currency).tag(currency)
                            }
                            Text("Other...").tag("OTHER")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityLabel("Currency")
                        .onChange(of: selectedCurrency) {
                            if selectedCurrency == "OTHER" {
                                isCustomCurrency = true
                                customCurrencyCode = ""
                            }
                        }
                    }
                }
                Divider()
                
                // Amount Input
                HStack {
                    Text(selectedCurrency)
                        .foregroundColor(AppTheme.textSecondary)
                        .font(.caption)
                        .frame(width: 35, alignment: .leading)
                    
                    TextField("Amount", value: $originalAmountInput, format: .number)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                // Exchange Rate (Only if not CHF)
                if selectedCurrency != "CHF" {
                    Divider()
                    HStack {
                        Text("Rate (1 \(selectedCurrency) = ? CHF)")
                            .foregroundColor(AppTheme.textSecondary)
                            .font(.caption)
                        
                        TextField("Rate", value: $exchangeRate, format: .number.precision(.fractionLength(0...6)))
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                    }
                    
                    if let base = baseAmountCHF {
                        Divider()
                        HStack {
                            Text("Total in CHF:")
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text(base, format: .currency(code: "CHF"))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                    }
                }

                Divider()
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Divider()
                
                HStack {
                    Picker("Category", selection: $category) {
                         Text("Select a category").tag("")
                        ForEach(type == "Income" ? categoryManager.incomeCategories : categoryManager.expenseCategories, id: \.self) {
                            Text($0)
                        }
                    }
                    Spacer()
                    Button { showCategorySheet = true } label: {
                        Image(systemName: "pencil.and.list.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("Manage categories")
                    .accessibilityLabel("Manage categories")
                }
              }
            }
        }
    }

    private var carExpensesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Car Expenses").font(AppTheme.headlineFont).foregroundColor(AppTheme.textSecondary)
            CardView {
                TextField("Kilometers", value: $carKilometers, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bill Attachment").font(AppTheme.headlineFont).foregroundColor(AppTheme.textSecondary)
            CardView {
              VStack(spacing: 15) {
                if let data = attachmentData, let type = attachmentType {
                    if type == "image", let uiImage = XImage(data: data) {
                        Image(xImage: uiImage)
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .frame(maxHeight: 200)
                    } else if type == "pdf" {
                        Label(attachmentFilename ?? "PDF Document", systemImage: "doc.text.fill")
                            .font(.headline)
                            .foregroundColor(AppTheme.textPrimary)
                    }
                } else {
                    Text("No attachment selected.")
                        .foregroundColor(AppTheme.textSecondary)
                        .italic()
                }
                
                HStack(spacing: 20) {
                    Spacer()
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Label("Select Photo", systemImage: "photo.on.rectangle.angled")
                    }
                    
                    Button { showingFileImporter = true } label: {
                        Label("Select PDF", systemImage: "doc.fill")
                    }
                    
                    if attachmentData != nil {
                        Button(role: .destructive) {
                            attachmentData = nil
                            attachmentType = nil
                            attachmentFilename = nil
                            selectedPhotoItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .help("Remove attachment")
                        .accessibilityLabel("Remove attachment")
                    }
                    Spacer()
                }
                .tint(AppTheme.accent)
              }
              .frame(maxWidth: .infinity)
            }
        }
    }
    
    /// Whether the amount, currency and rate are all exactly as stored.
    private func moneyIsUnchanged(from transaction: TransactionItem?) -> Bool {
        guard let transaction else { return false }
        let storedCode = transaction.currencyCode ?? "CHF"
        let storedOriginal = transaction.originalAmount > 0
            ? transaction.originalAmount
            : transaction.amount
        return selectedCurrency == storedCode
            && originalAmountInput == storedOriginal
            && exchangeRate == storedExchangeRate
    }

    /// Fills in a previously-used title and the classification that usually goes
    /// with it.
    ///
    /// The amount is deliberately left alone: it is the one field that normally
    /// differs between two transactions sharing a title.
    private func apply(_ suggestion: TitleSuggestion) {
        details = suggestion.title
        isApplyingStoredValues = true
        defer { isApplyingStoredValues = false }

        guard let previous = TitleSuggestionStore.mostRecentTransaction(
            withTitle: suggestion.title, in: viewContext
        ) else { return }

        // Type first: it decides which categories are offered.
        if let previousType = previous.type, !previousType.isEmpty {
            type = previousType
        }
        if let previousCategory = previous.category, !previousCategory.isEmpty {
            category = previousCategory
        }
        if let previousCurrency = previous.currencyCode, !previousCurrency.isEmpty,
           previousCurrency != "OTHER" {
            selectedCurrency = previousCurrency
            isCustomCurrency = false
            if previousCurrency != "CHF", previous.originalAmount > 0 {
                // Carry the rate over as a starting point; the amount stays empty.
                exchangeRate = previous.amount / previous.originalAmount
            }
        }
    }

    /// Populates the form from the edited object exactly once.
    ///
    /// This used to run from `.onAppear`, which fires again whenever the view
    /// reappears — including on return from the category-management sheet — and
    /// silently overwrote every field the user had just typed.
    private func loadTransactionDataOnce() {
        guard !hasLoadedTransaction else { return }
        hasLoadedTransaction = true
        isApplyingStoredValues = true
        loadTransactionData()
        isApplyingStoredValues = false
    }

    private func loadTransactionData() {
        if transactionToEdit == nil, let source = prefillSource {
            // A duplicate: copy the classification, keep today's date, and leave
            // the amount and any attachment for the user to supply.
            type = source.type ?? "Expense"
            details = source.details ?? ""
            category = source.category ?? ""
            selectedCurrency = source.currencyCode ?? "CHF"
            if source.currencyCode != "CHF", source.originalAmount > 0 {
                exchangeRate = source.amount / source.originalAmount
            }
            return
        }

        if let transaction = transactionToEdit {
            type = transaction.type ?? "Expense"
            details = transaction.details ?? ""
            date = transaction.date ?? .now
            category = transaction.category ?? ""
            
            // Logic to reverse engineer the display for edit mode
            let storedCHF = transaction.amount
            let storedCode = transaction.currencyCode ?? "CHF"
            let storedOriginal = transaction.originalAmount
            
            selectedCurrency = storedCode
            
            if storedCode == "CHF" {
                originalAmountInput = storedCHF
                storedExchangeRate = 1.0
                exchangeRate = 1.0
            } else {
                originalAmountInput = storedOriginal > 0 ? storedOriginal : storedCHF
                storedExchangeRate = storedOriginal > 0 ? storedCHF / storedOriginal : 1.0
                exchangeRate = storedExchangeRate
            }
            
            attachmentData = transaction.billImage
            attachmentType = transaction.billType
            attachmentFilename = transaction.billFilename
            
            if transaction.carKilometers > 0 {
                carKilometers = transaction.carKilometers
            }
        }
    }

    private func saveTransaction() {
        guard let finalBaseAmount = baseAmountCHF, let originalAmount = originalAmountInput else { return }
        
        let transaction = transactionToEdit ?? TransactionItem(context: viewContext)
        // Backfill rather than only assigning on insert: rows saved by earlier
        // builds can have a nil id, and anything keyed on it then collides.
        if transaction.id == nil {
            transaction.id = UUID()
        }
        
        transaction.date = date
        transaction.details = details
        
        // IMPORTANT: Storing the Base CHF amount for Reports
        transaction.amount = finalBaseAmount
        // Storing original info for UI
        transaction.currencyCode = selectedCurrency
        transaction.originalAmount = originalAmount
        
        transaction.type = type
        transaction.category = category
        
        transaction.billImage = attachmentData
        transaction.billType = attachmentType
        transaction.billFilename = attachmentFilename

        if category == ReportGenerator.carExpensesCategory {
            transaction.carKilometers = carKilometers ?? 0
        } else {
            transaction.carKilometers = 0
        }

        if let message = viewContext.saveOrRollback() {
            saveErrorMessage = message
            return
        }
        // Add currency to used list if new
        userSettings.addCurrency(selectedCurrency)
        dismiss()
    }
}
