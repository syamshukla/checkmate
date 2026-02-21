//
//  LineItem.swift
//  CheckMate
//
//  Created by Syam Shukla on 2/18/26.
//

import Foundation
import SwiftData

@Model
final class LineItem {
    var name: String
    var price: Double
    var quantity: Int = 1

    var receipt: Receipt?

    // Many-to-many: multiple people can share a single item
    @Relationship(deleteRule: .nullify) var assignedPeople: [Person] = []

    /// Per-person portion counts for unequal splits on multi-quantity items.
    /// Key = person.personID, value = how many units that person took.
    /// Empty = fall back to equal split among all assignedPeople.
    var portionMap: [String: Int] = [:]

    init(
        name: String,
        price: Double,
        quantity: Int = 1
    ) {
        self.name = name
        self.price = price
        self.quantity = quantity
    }

    var totalPrice: Double {
        price * Double(quantity)
    }

    /// How much a specific person owes for this item.
    /// Uses portionMap when set — always proportional by weight so it works for
    /// both multi-quantity items (weight = units claimed) and single items (weight = ratio share).
    func amountOwed(byPersonID id: String) -> Double {
        guard assignedPeople.contains(where: { $0.personID == id }) else { return 0 }
        if !portionMap.isEmpty,
           let myWeight = portionMap[id], myWeight > 0 {
            let totalWeight = portionMap.values.reduce(0, +)
            guard totalWeight > 0 else { return 0 }
            return totalPrice * Double(myWeight) / Double(totalWeight)
        }
        return totalPrice / Double(max(1, assignedPeople.count))
    }
}
