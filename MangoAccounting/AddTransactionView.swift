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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Type", selection: $type) {
                    ForEach(types, id: \.self) { Text(LocalizedStringKey($0)) }
                }
                .pickerStyle(.segmented)

                detailsSection

                if category == "Car Expenses" {
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
        .task { loadTransactionDataOnce() }
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
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details").font(AppTheme.headlineFont).foregroundColor(AppTheme.textSecondary)
            VStack {
                TextField("Description (e.g., Lunch with client)", text: $details)
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
                        Picker("", selection: $selectedCurrency) {
                            ForEach(userSettings.usedCurrencies, id: \.self) { currency in
                                Text(currency).tag(currency)
                            }
                            Text("Other...").tag("OTHER")
                        }
                        .pickerStyle(.menu)
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
                        
                        TextField("Rate", value: $exchangeRate, format: .number)
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
                    Button { showCategorySheet = true } label: { Image(systemName: "pencil.and.list.clipboard") }
                        .buttonStyle(.borderless)
                }
            }
            .padding()
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cornerRadius)
        }
    }
    
    private var carExpensesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Car Expenses").font(AppTheme.headlineFont).foregroundColor(AppTheme.textSecondary)
            VStack {
                TextField("Kilometers", value: $carKilometers, format: .number)
            }
            .padding()
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cornerRadius)
        }
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bill Attachment").font(AppTheme.headlineFont).foregroundColor(AppTheme.textSecondary)
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
                    }
                    Spacer()
                }
                .tint(AppTheme.accent)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(AppTheme.cardBackground)
            .cornerRadius(AppTheme.cornerRadius)
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
        loadTransactionData()
    }

    private func loadTransactionData() {
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
                exchangeRate = 1.0
            } else {
                originalAmountInput = storedOriginal > 0 ? storedOriginal : storedCHF
                // Calculate rate roughly if original exists, otherwise 1.0
                if storedOriginal > 0 {
                    exchangeRate = storedCHF / storedOriginal
                } else {
                    exchangeRate = 1.0
                }
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
        if transactionToEdit == nil {
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

        if category == "Car Expenses" {
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
