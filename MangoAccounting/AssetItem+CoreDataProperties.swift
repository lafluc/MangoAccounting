import Foundation
import CoreData

extension AssetItem {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AssetItem> {
        return NSFetchRequest<AssetItem>(entityName: "AssetItem")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var purchaseDate: Date?
    @NSManaged public var purchasePrice: Double
    @NSManaged public var depreciationRate: Double
    @NSManaged public var isLinear: Bool
    @NSManaged public var currencyCode: String?
    @NSManaged public var originalPrice: Double
}

extension AssetItem: Identifiable {}

// MARK: - Depreciation Logic
extension AssetItem {
    func depreciation(forYear targetYear: Int) -> Double {
        guard let pDate = purchaseDate, purchasePrice > 0, depreciationRate > 0 else { return 0 }
        let pYear = Calendar.current.component(.year, from: pDate)

        if targetYear < pYear { return 0 }

        let yearsActive = targetYear - pYear
        let rate = depreciationRate / 100.0

        if isLinear {
            let accumulatedBefore = Double(yearsActive) * (purchasePrice * rate)
            if accumulatedBefore >= purchasePrice { return 0 }

            let currentDepreciation = purchasePrice * rate
            if accumulatedBefore + currentDepreciation > purchasePrice {
                return purchasePrice - accumulatedBefore
            }
            return currentDepreciation
        } else {
            let bookValueBefore = purchasePrice * pow(1.0 - rate, Double(yearsActive))
            if bookValueBefore <= 1.0 { return 0 }

            let currentDepreciation = bookValueBefore * rate
            if bookValueBefore - currentDepreciation < 1.0 {
                return bookValueBefore - 1.0
            }
            return currentDepreciation
        }
    }

    func bookValue(atEndOfYear targetYear: Int) -> Double {
        guard purchasePrice > 0, let pDate = purchaseDate else { return 0 }

        let purchaseYear = Calendar.current.component(.year, from: pDate)
        if targetYear < purchaseYear {
            return purchasePrice
        }

        let cumulativeDepreciation = (purchaseYear...targetYear).reduce(0.0) { partial, year in
            partial + depreciation(forYear: year)
        }

        return max(1.0, purchasePrice - cumulativeDepreciation)
    }
}
