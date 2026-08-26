// TransactionDetailView.swift

import SwiftUI

struct TransactionDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var transaction: TransactionItem
    
    @State private var showDeleteConfirmation = false
    @State private var saveErrorMessage: String?
    @State private var showEditSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                attachmentView // Updated view for attachments
                detailsCard
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Transaction Details")
        .background(AppTheme.background.ignoresSafeArea())
        .toolbar { detailToolbar }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                AddTransactionView(transactionToEdit: transaction)
            }
            .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 680)
        }
        .alert("Are you sure?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteTransaction() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This transaction will be permanently deleted.")
        }
        .alert(
            "Could Not Delete",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 480, minHeight: 560)
        #endif
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var attachmentView: some View {
        // This view now intelligently decides whether to show an image, a PDF, or a placeholder.
        if let data = transaction.billImage, let type = transaction.billType {
            if type == "image", let uiImage = XImage(data: data) {
                Image(xImage: uiImage)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .shadow(color: AppTheme.shadow.color, radius: AppTheme.shadow.radius, x: AppTheme.shadow.x, y: AppTheme.shadow.y)
            } else if type == "pdf" {
                VStack(alignment: .leading, spacing: 0) {
                    if let filename = transaction.billFilename {
                        Text(filename)
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(AppTheme.cardBackground)
                    }
                    PDFKitView(data: data)
                        .frame(height: 500) // Default height for the PDF view
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .shadow(color: AppTheme.shadow.color, radius: AppTheme.shadow.radius, x: AppTheme.shadow.x, y: AppTheme.shadow.y)

            } else {
                noAttachmentPlaceholder
            }
        // For backward compatibility with transactions saved before billType existed
        } else if let imageData = transaction.billImage, let uiImage = XImage(data: imageData) {
            Image(xImage: uiImage)
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .shadow(color: AppTheme.shadow.color, radius: AppTheme.shadow.radius, x: AppTheme.shadow.x, y: AppTheme.shadow.y)
        } else {
            noAttachmentPlaceholder
        }
    }
    
    private var noAttachmentPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark").font(.system(size: 50))
            Text("No Bill Photo").font(.headline)
        }
        .foregroundColor(AppTheme.textSecondary.opacity(0.5))
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(AppTheme.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
    
    private var detailsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 0) {
                financialDetails
                classificationDetails
            }
        }
    }
    
    private var financialDetails: some View {
        Group {
            detailRow(label: "Description", value: transaction.details ?? "N/A")
            Divider().padding(.horizontal)
            detailRow(label: "Amount", value: transaction.amount)
            Divider().padding(.horizontal)
            detailRow(label: "Date", value: transaction.date ?? .now)
        }
    }
    
    private var classificationDetails: some View {
        Group {
            Divider().padding(.horizontal)
            detailRow(label: "Type", value: transaction.type ?? "N/A")
            Divider().padding(.horizontal)
            detailRow(label: "Category", value: transaction.category ?? "N/A")
        }
    }
    
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showEditSheet = true } label: { Label("Edit", systemImage: "pencil") }
            .tint(AppTheme.accent)
            
            Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("Delete", systemImage: "trash") }
             .tint(AppTheme.negative)
        }
    }
    
    // MARK: - Helper Functions
    
    private func deleteTransaction() {
        viewContext.delete(transaction)
        if let message = viewContext.saveOrRollback() {
            saveErrorMessage = message
            return
        }
        dismiss()
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(label)).foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(LocalizedStringKey(value)).fontWeight(.medium).foregroundColor(AppTheme.textPrimary)
        }.padding()
    }
    
    private func detailRow(label: String, value: Date) -> some View {
        HStack {
            Text(LocalizedStringKey(label)).foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value.formatted(date: .long, time: .omitted)).fontWeight(.medium).foregroundColor(AppTheme.textPrimary)
        }.padding()
    }

    private func detailRow(label: String, value: Double) -> some View {
        HStack {
            Text(LocalizedStringKey(label)).foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value, format: .currency(code: "CHF"))
                .fontWeight(.medium)
                .foregroundColor(transaction.type == "Income" ? AppTheme.positive : AppTheme.negative)
        }.padding()
    }
}
