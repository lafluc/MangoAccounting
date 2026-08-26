// CategoryManagementSheet.swift

import SwiftUI
import CoreData

struct CategoryManagementSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var categoryManager = CategoryManager.shared
    
    @State private var newIncomeCategory: String = ""
    @State private var newExpenseCategory: String = ""

    // NEW: Renaming State
    @State private var categoryToRename: String?
    @State private var newCategoryName: String = ""
    @State private var renameErrorMessage: String?
    @State private var isRenamingIncome: Bool = false
    @State private var showRenameAlert = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SectionView(title: "Income Categories") {
                        VStack {
                            ForEach(categoryManager.incomeCategories, id: \.self) { category in
                                HStack {
                                    Text(category)
                                    Spacer()
                                    
                                    // NEW: Edit Button
                                    Button {
                                        categoryToRename = category
                                        newCategoryName = category
                                        isRenamingIncome = true
                                        showRenameAlert = true
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 8)
                                    .foregroundColor(AppTheme.accent)

                                    Button(role: .destructive) { deleteIncome(category: category) } label: { Image(systemName: "trash") }
                                        .buttonStyle(.plain)
                                }
                                if category != categoryManager.incomeCategories.last { Divider() }
                            }
                            Divider()
                            HStack {
                                TextField("New Income Category", text: $newIncomeCategory)
                                Button("Add", action: addIncomeCategory).disabled(newIncomeCategory.isEmpty)
                            }
                        }
                        .padding()
                        .background(AppTheme.cardBackground)
                        .cornerRadius(AppTheme.cornerRadius)
                    }
                    
                    SectionView(title: "Expense Categories") {
                        VStack {
                            ForEach(categoryManager.expenseCategories, id: \.self) { category in
                                HStack {
                                    Text(category)
                                    Spacer()
                                    
                                    // NEW: Edit Button
                                    Button {
                                        categoryToRename = category
                                        newCategoryName = category
                                        isRenamingIncome = false
                                        showRenameAlert = true
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 8)
                                    .foregroundColor(AppTheme.accent)
                                    
                                    Button(role: .destructive) { deleteExpense(category: category) } label: { Image(systemName: "trash") }
                                        .buttonStyle(.plain)
                                }
                                if category != categoryManager.expenseCategories.last { Divider() }
                            }
                            Divider()
                            HStack {
                                TextField("New Expense Category", text: $newExpenseCategory)
                                Button("Add", action: addExpenseCategory).disabled(newExpenseCategory.isEmpty)
                            }
                        }
                        .padding()
                        .background(AppTheme.cardBackground)
                        .cornerRadius(AppTheme.cornerRadius)
                    }
                }
                .padding()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Manage Categories")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // NEW: Rename Alert
            .alert("Rename Category", isPresented: $showRenameAlert) {
                TextField("New Category Name", text: $newCategoryName)
                Button("Save") {
                    if let oldName = categoryToRename, !newCategoryName.isEmpty, oldName != newCategoryName {
                        renameCategory(oldName: oldName, newName: newCategoryName, isIncome: isRenamingIncome)
                    }
                }
                Button("Cancel", role: .cancel) {
                    categoryToRename = nil
                }
            } message: {
                Text("This will also update all existing transactions that use this category.")
            }
            .alert(
                "Could Not Rename",
                isPresented: Binding(
                    get: { renameErrorMessage != nil },
                    set: { if !$0 { renameErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { renameErrorMessage = nil }
            } message: {
                Text(renameErrorMessage ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 450, minHeight: 400)
        #endif
    }
    
    // MARK: - Core Logic
    
    private func addIncomeCategory() {
        guard !newIncomeCategory.isEmpty else { return }
        withAnimation {
            categoryManager.incomeCategories.append(newIncomeCategory)
            newIncomeCategory = ""
        }
    }
    
    private func deleteIncome(category: String) {
        if let index = categoryManager.incomeCategories.firstIndex(of: category) {
            categoryManager.incomeCategories.remove(at: index)
        }
    }
    
    private func addExpenseCategory() {
        guard !newExpenseCategory.isEmpty else { return }
        withAnimation {
            categoryManager.expenseCategories.append(newExpenseCategory)
            newExpenseCategory = ""
        }
    }
    
    private func deleteExpense(category: String) {
        if let index = categoryManager.expenseCategories.firstIndex(of: category) {
            categoryManager.expenseCategories.remove(at: index)
        }
    }
    
    // NEW: Function to rename and cascade changes to old transactions
    private func renameCategory(oldName: String, newName: String, isIncome: Bool) {
        // 1. Update CategoryManager arrays
        withAnimation {
            if isIncome {
                if let idx = categoryManager.incomeCategories.firstIndex(of: oldName) {
                    categoryManager.incomeCategories[idx] = newName
                }
            } else {
                if let idx = categoryManager.expenseCategories.firstIndex(of: oldName) {
                    categoryManager.expenseCategories[idx] = newName
                }
            }
        }
        
        // 2. Cascade changes to Core Data transactions
        let request: NSFetchRequest<TransactionItem> = TransactionItem.fetchRequest()
        request.predicate = NSPredicate(format: "category == %@", oldName)
        
        do {
            let transactionsToUpdate = try viewContext.fetch(request)
            for transaction in transactionsToUpdate {
                transaction.category = newName
            }
            if let message = viewContext.saveOrRollback() {
                renameErrorMessage = message
            }
        } catch {
            renameErrorMessage = (error as NSError).localizedDescription
        }
    }
}
