//
//  CategoryManager.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 20.08.2025.
//

import SwiftUI
import Combine

class CategoryManager: ObservableObject {
    static let shared = CategoryManager()

    @AppStorage("income_categories") private var incomeCategoriesData: Data = Data()
    @AppStorage("expense_categories") private var expenseCategoriesData: Data = Data()

    @Published var incomeCategories: [String] = [] {
        didSet { save(incomeCategories, to: &incomeCategoriesData) }
    }
    @Published var expenseCategories: [String] = [] {
        didSet { save(expenseCategories, to: &expenseCategoriesData) }
    }

    private init() {
        // Load existing user-created categories.
        self.incomeCategories = Self.load(from: incomeCategoriesData)
        self.expenseCategories = Self.load(from: expenseCategoriesData)
        
        // MODIFICATION: Add default expense categories if they don't already exist.
        addDefaultCategoriesIfNeeded()
    }

    // MODIFICATION: New function to add default categories
    private func addDefaultCategoriesIfNeeded() {
        let defaultExpenseCategories = [ReportGenerator.carExpensesCategory]
        for category in defaultExpenseCategories {
            if !expenseCategories.contains(category) {
                expenseCategories.append(category)
            }
        }
    }
    
    private func save(_ categories: [String], to dataStore: inout Data) {
        if let data = try? JSONEncoder().encode(categories) {
            dataStore = data
        }
    }
    
    private static func load(from data: Data) -> [String] {
        if let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }
        // If decoding fails or there's no data, return an empty array.
        return []
    }
}
