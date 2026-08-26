import SwiftUI
import CoreData

struct AssetsListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AssetItem.purchaseDate, ascending: false)],
        animation: .default)
    private var assets: FetchedResults<AssetItem>
    
    @State private var showAddSheet = false
    @State private var assetToEdit: AssetItem?
    
    // Deletion State
    @State private var assetToDelete: AssetItem?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationView {
            Group {
                if assets.isEmpty {
                    PlaceholderView(
                        systemImageName: "briefcase.fill",
                        title: "No Assets Yet",
                        subtitle: "Track your cameras, lenses, and IT equipment for automatic depreciation."
                    )
                } else {
                    List {
                        ForEach(assets) { asset in
                            Button {
                                assetToEdit = asset
                            } label: {
                                AssetRowView(asset: asset)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            // Right-click context menu for macOS
                            .contextMenu {
                                Button(role: .destructive) {
                                    assetToDelete = asset
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete Asset", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.background)
                }
            }
            .navigationTitle("Business Assets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: { Label("Add", systemImage: "plus.circle.fill") }
                    .tint(AppTheme.accent)
                }
            }
            .sheet(isPresented: $showAddSheet) {
                NavigationView {
                    AddAssetView()
                }
                .frame(minWidth: 500, minHeight: 650)
            }
            .sheet(item: $assetToEdit) { asset in
                NavigationView {
                    AddAssetView(assetToEdit: asset)
                }
                .frame(minWidth: 500, minHeight: 650)
            }
            // Deletion Safety Alert
            .alert("Delete Asset", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let asset = assetToDelete {
                        viewContext.delete(asset)
                        try? viewContext.save()
                    }
                }
                Button("Cancel", role: .cancel) {
                    assetToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this asset? This action cannot be undone.")
            }
        }
    }
}

struct AssetRowView: View {
    @ObservedObject var asset: AssetItem
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "camera.macro")
                .font(.title2)
                .foregroundColor(AppTheme.accent)
                .frame(width: 25)

            VStack(alignment: .leading, spacing: 4) {
                Text(asset.name ?? "Unknown Asset")
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary)
                
                Text("\(asset.isLinear ? "Linear" : "Degressive") • \(asset.depreciationRate, specifier: "%.1f")%")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
            }
            
            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(asset.purchasePrice, format: .currency(code: "CHF"))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.textPrimary)
                Text(asset.purchaseDate ?? .now, style: .date)
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 8)
    }
}
