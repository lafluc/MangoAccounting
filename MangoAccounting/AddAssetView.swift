import SwiftUI

enum AssetCategory: String, CaseIterable, Identifiable {
    case it = "IT & Computer"
    case camera = "Camera & Production Gear"
    case vehicle = "Vehicles"
    case furniture = "Office Furniture"
    case custom = "Custom Rate"

    var id: String { self.rawValue }

    var defaultDegressiveRate: Double {
        switch self {
        case .it: return 40.0
        case .camera: return 30.0
        case .vehicle: return 40.0
        case .furniture: return 25.0
        case .custom: return 0.0
        }
    }
}

struct AddAssetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var userSettings = UserSettings()

    var assetToEdit: AssetItem?

    @State private var name: String = ""
    @State private var purchaseDate: Date = .now
    @State private var depreciationRate: Double?
    @State private var isLinear: Bool = false
    @State private var selectedAssetCategory: AssetCategory = .custom

    @State private var selectedCurrency: String = "CHF"
    @State private var isCustomCurrency: Bool = false
    @State private var customCurrencyCode: String = ""
    @State private var originalPriceInput: Double?
    @State private var exchangeRate: Double = 1.0

    @State private var showDeleteConfirmation = false
    @State private var saveErrorMessage: String?

    private var basePriceCHF: Double? {
        guard let original = originalPriceInput else { return nil }
        if selectedCurrency == "CHF" {
            return original
        }
        return original * exchangeRate
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionView(title: "Asset Details") {
                        CardView {
                            VStack(spacing: 12) {
                                TextField("Asset Name (e.g., RED Komodo)", text: $name)
                                    .textFieldStyle(.roundedBorder)

                                Divider()

                                HStack {
                                    Text("Currency")
                                        .foregroundColor(AppTheme.textSecondary)
                                    Spacer()

                                    if isCustomCurrency {
                                        TextField("Code", text: $customCurrencyCode)
                                            .frame(width: 60)
                                            .textFieldStyle(.roundedBorder)
                                        Button("OK") {
                                            let trimmed = customCurrencyCode
                                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                                .uppercased()

                                            guard !trimmed.isEmpty else { return }
                                            userSettings.addCurrency(trimmed)
                                            selectedCurrency = trimmed
                                            isCustomCurrency = false
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

                                HStack {
                                    Text(selectedCurrency)
                                        .foregroundColor(AppTheme.textSecondary)
                                        .font(.caption)
                                        .frame(width: 35, alignment: .leading)

                                    TextField("Purchase Price", value: $originalPriceInput, format: .number)
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                        .textFieldStyle(.roundedBorder)
                                }

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
                                            .textFieldStyle(.roundedBorder)
                                    }

                                    if let base = basePriceCHF {
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

                                DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    SectionView(title: "Depreciation Settings") {
                        CardView {
                            VStack(spacing: 12) {
                                Picker("Asset Class (ESTV)", selection: $selectedAssetCategory) {
                                    ForEach(AssetCategory.allCases) { category in
                                        Text(category.rawValue).tag(category)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: selectedAssetCategory) {
                                    if selectedAssetCategory != .custom {
                                        depreciationRate = selectedAssetCategory.defaultDegressiveRate
                                        isLinear = false
                                    }
                                }

                                Divider()

                                Toggle("Linear Depreciation", isOn: $isLinear)
                                    .tint(AppTheme.accent)
                                    .onChange(of: isLinear) {
                                        if let currentRate = depreciationRate, selectedAssetCategory != .custom {
                                            if isLinear {
                                                depreciationRate = currentRate / 2.0
                                            } else {
                                                depreciationRate = currentRate * 2.0
                                            }
                                        }
                                    }

                                Divider()

                                HStack {
                                    Text("Yearly Rate (%)")
                                    Spacer()
                                    TextField("e.g. 40", value: $depreciationRate, format: .number)
                                        .multilineTextAlignment(.trailing)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Text("Note: ESTV standard degressive rates are 40% for IT & Vehicles, 30% for Camera Gear, and 25% for Furniture. Linear rates are exactly half.")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.horizontal)
                }
                .padding(24)
            }

            VStack(spacing: 12) {
                Button(assetToEdit == nil ? "Save Asset" : "Update Asset") { saveAsset() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        originalPriceInput == nil ||
                        depreciationRate == nil ||
                        (selectedCurrency != "CHF" && exchangeRate <= 0)
                    )

                if assetToEdit != nil {
                    Button("Delete Asset", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .buttonStyle(PillButtonStyle())
                    .tint(.red)
                }
            }
            .padding()
            .background(AppTheme.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(assetToEdit == nil ? "New Asset" : "Edit Asset")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
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
        .onAppear {
            if let asset = assetToEdit {
                name = asset.name ?? ""
                purchaseDate = asset.purchaseDate ?? .now
                depreciationRate = asset.depreciationRate
                isLinear = asset.isLinear

                let storedCHF = asset.purchasePrice
                let storedCode = (asset.currencyCode?.isEmpty == false ? asset.currencyCode : "CHF") ?? "CHF"
                let storedOriginal = asset.originalPrice

                selectedCurrency = storedCode
                userSettings.addCurrency(storedCode)

                if storedCode == "CHF" {
                    originalPriceInput = storedOriginal > 0 ? storedOriginal : storedCHF
                    exchangeRate = 1.0
                } else {
                    originalPriceInput = storedOriginal > 0 ? storedOriginal : storedCHF
                    if storedOriginal > 0 {
                        exchangeRate = storedCHF / storedOriginal
                    } else {
                        exchangeRate = 1.0
                    }
                }

                if let match = AssetCategory.allCases.first(where: {
                    ($0.defaultDegressiveRate == asset.depreciationRate && !asset.isLinear) ||
                    (($0.defaultDegressiveRate / 2.0) == asset.depreciationRate && asset.isLinear)
                }) {
                    selectedAssetCategory = match
                }
            }
        }
        .alert("Delete Asset", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteAsset()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this asset? This action cannot be undone.")
        }
    }

    private func saveAsset() {
        guard
            let original = originalPriceInput,
            let baseCHF = basePriceCHF,
            let rate = depreciationRate,
            baseCHF > 0,
            rate > 0
        else {
            return
        }

        let asset = assetToEdit ?? AssetItem(context: viewContext)
        // Backfill rather than only assigning on insert: rows saved by earlier
        // builds can have a nil id, and anything keyed on it then collides.
        if asset.id == nil {
            asset.id = UUID()
        }

        asset.name = name
        asset.purchasePrice = baseCHF
        asset.purchaseDate = purchaseDate
        asset.depreciationRate = rate
        asset.isLinear = isLinear
        asset.currencyCode = selectedCurrency
        asset.originalPrice = original

        if let message = viewContext.saveOrRollback() {
            saveErrorMessage = message
            return
        }
        userSettings.addCurrency(selectedCurrency)
        dismiss()
    }

    private func deleteAsset() {
        guard let asset = assetToEdit else { return }
        viewContext.delete(asset)
        if let message = viewContext.saveOrRollback() {
            // Without the rollback in saveOrRollback the asset would vanish from
            // the UI but survive on disk, reappearing on the next launch.
            saveErrorMessage = message
            return
        }
        dismiss()
    }
}
