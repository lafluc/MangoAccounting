import SwiftUI
import CoreData

struct AssetsListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AssetItem.purchaseDate, ascending: false)],
        animation: .default)
    private var assets: FetchedResults<AssetItem>
    
    /// Which editor sheet is open. One piece of state, not one flag per sheet:
    /// SwiftUI honours a single `.sheet` modifier per view, so the two stacked
    /// here meant only one of Add and Edit ever opened.
    private enum ActiveSheet: Identifiable {
        case add
        case edit(ManagedObjectBox<AssetItem>)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let box): return "edit:\(box.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var alert: AlertRequest?

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
                        ForEach(assets, id: \.objectID) { asset in
                            Button {
                                activeSheet = .edit(ManagedObjectBox(asset))
                            } label: {
                                AssetRowView(asset: asset)
                                    // The row is mostly Spacer, which is not
                                    // hit-testable, so clicking an asset only
                                    // opened the editor when the pointer was over
                                    // its name.
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            // Right-click context menu for macOS
                            .contextMenu {
                                Button(role: .destructive) {
                                    requestDelete(asset)
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
                    Button { activeSheet = .add } label: { Label("Add", systemImage: "plus.circle.fill") }
                    .tint(AppTheme.accent)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                NavigationStack {
                    switch sheet {
                    case .add:
                        AddAssetView()
                    case .edit(let box):
                        AddAssetView(assetToEdit: box.object)
                    }
                }
                .frame(minWidth: 500, minHeight: 650)
            }
            .appAlert($alert)
        }
    }
}

private extension AssetsListView {

    func requestDelete(_ asset: AssetItem) {
        alert = .confirm(
            title: "Delete Asset",
            message: Text("Are you sure you want to delete this asset? This action cannot be undone."),
            label: "Delete"
        ) {
            viewContext.delete(asset)
            if let message = viewContext.saveOrRollback() {
                alert = .error("Could Not Delete", message)
            }
        }
    }
}

struct AssetRowView: View {
    @ObservedObject var asset: AssetItem
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "camera.macro")
                .accessibilityHidden(true)
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
