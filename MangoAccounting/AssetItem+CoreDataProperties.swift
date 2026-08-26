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

    /// Residual value a degressive schedule stops at.
    ///
    /// Declining-balance depreciation never mathematically reaches zero, so leaving
    /// CHF 1 on the books is the usual convention. Linear depreciation does reach
    /// zero and is not floored — flooring it left book value permanently
    /// disagreeing with the accumulated depreciation reported beside it.
    static let degressiveResidual: Double = 1.0

    /// Number of annual charges taken by the end of `targetYear`.
    ///
    /// The purchase year takes a full charge, matching how the app has always
    /// calculated it.
    private func chargeCount(throughYear targetYear: Int) -> Int {
        guard let purchaseDate else { return 0 }
        return max(0, targetYear - FiscalCalendar.year(of: purchaseDate) + 1)
    }

    /// Closed-form book value after a number of annual charges, unrounded.
    ///
    /// Computed directly rather than as cost minus a running sum: summing rounded
    /// yearly charges over decades left the degressive residual a rappen off its
    /// floor.
    private func rawBookValue(afterCharges charges: Int) -> Double {
        guard purchasePrice > 0 else { return 0 }
        guard charges > 0 else { return purchasePrice }

        let rate = depreciationRate / 100.0
        guard rate > 0 else { return purchasePrice }

        if isLinear {
            return max(0, purchasePrice - Double(charges) * purchasePrice * rate)
        }
        return max(Self.degressiveResidual, purchasePrice * pow(1.0 - rate, Double(charges)))
    }

    /// This year's depreciation charge.
    func depreciation(forYear targetYear: Int) -> Double {
        guard purchasePrice > 0, let purchaseDate, depreciationRate > 0 else { return 0 }
        guard targetYear >= FiscalCalendar.year(of: purchaseDate) else { return 0 }

        // Defined as the drop in book value, so the two always reconcile.
        let opening = rawBookValue(afterCharges: chargeCount(throughYear: targetYear - 1))
        let closing = rawBookValue(afterCharges: chargeCount(throughYear: targetYear))
        return Money.roundToCents(opening - closing)
    }

    func bookValue(atEndOfYear targetYear: Int) -> Double {
        guard purchasePrice > 0, let purchaseDate else { return 0 }

        // An asset that did not exist yet carries no book value. This returned the
        // full purchase price, inflating total assets on every balance sheet for a
        // year before the item was bought.
        guard targetYear >= FiscalCalendar.year(of: purchaseDate) else { return 0 }

        return Money.roundToCents(rawBookValue(afterCharges: chargeCount(throughYear: targetYear)))
    }
}
