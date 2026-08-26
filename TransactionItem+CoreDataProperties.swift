//
//  TransactionItem+CoreDataProperties.swift
//  MangoAccounting
//
//  Created by Luc Lafrenaye on 14.08.2025.
//

import Foundation
import CoreData

extension TransactionItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TransactionItem> {
        return NSFetchRequest<TransactionItem>(entityName: "TransactionItem")
    }

    @NSManaged public var amount: Double // Always stored in CHF for reporting consistency
    @NSManaged public var category: String?
    @NSManaged public var date: Date?
    @NSManaged public var details: String?
    @NSManaged public var id: UUID?
    @NSManaged public var type: String?
    @NSManaged public var carKilometers: Double
    @NSManaged public var billImage: Data?
    @NSManaged public var billType: String?
    @NSManaged public var billFilename: String?
    
    // NEW ATTRIBUTES
    @NSManaged public var currencyCode: String?
    @NSManaged public var originalAmount: Double // The amount in the foreign currency

}

extension TransactionItem : Identifiable {

}
