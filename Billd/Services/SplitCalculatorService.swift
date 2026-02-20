//
//  SplitCalculatorService.swift
//  CheckMate
//
//  Created by Syam Shukla on 2/18/26.
//

import Foundation

class SplitCalculatorService {
    static let shared = SplitCalculatorService()
    private init() {}

    /// Calculates each person's share of the bill.
    /// Items shared by multiple people are split equally among them.
    /// Tax, tip, and discount are distributed proportional to each person's item subtotal.
    func calculateSplit(
        lineItems: [LineItem],
        people: [Person],
        taxAmount: Double,
        tipAmount: Double,
        discountAmount: Double = 0
    ) -> [Person: SplitDetails] {

        // Seed all people at $0 so everyone appears in the result
        var personSubtotals: [ObjectIdentifier: Double] = [:]
        var personMap: [ObjectIdentifier: Person] = [:]
        for person in people {
            let key = ObjectIdentifier(person)
            personSubtotals[key] = 0.0
            personMap[key] = person
        }

        // Each assigned person pays item.totalPrice / assignedPeople.count
        for item in lineItems {
            guard !item.assignedPeople.isEmpty else { continue }
            let share = item.totalPrice / Double(item.assignedPeople.count)
            for person in item.assignedPeople {
                let key = ObjectIdentifier(person)
                personSubtotals[key, default: 0] += share
                if personMap[key] == nil { personMap[key] = person }
            }
        }

        let totalSubtotal = personSubtotals.values.reduce(0, +)
        let count = Double(personMap.count)

        var splits: [Person: SplitDetails] = [:]

        for (key, subtotal) in personSubtotals {
            guard let person = personMap[key] else { continue }

            let ratio = totalSubtotal > 0 ? subtotal / totalSubtotal : (count > 0 ? 1.0 / count : 0)
            let taxShare      =  ratio * taxAmount
            let tipShare      =  ratio * tipAmount
            let discountShare =  ratio * discountAmount
            let total         = subtotal + taxShare + tipShare - discountShare

            splits[person] = SplitDetails(
                subtotal: subtotal,
                tax: taxShare,
                tip: tipShare,
                discount: discountShare,
                total: max(0, total)
            )
        }

        return splits
    }

    /// Returns true only when every line item has at least one person assigned.
    func validateAllItemsAssigned(_ lineItems: [LineItem]) -> Bool {
        lineItems.allSatisfy { !$0.assignedPeople.isEmpty }
    }

    /// Quick summary statistics for display.
    func getSummary(_ lineItems: [LineItem]) -> SplitSummary {
        var people: Set<ObjectIdentifier> = []
        for item in lineItems {
            for p in item.assignedPeople { people.insert(ObjectIdentifier(p)) }
        }
        let assigned = lineItems.filter { !$0.assignedPeople.isEmpty }.count
        return SplitSummary(
            totalPeople: people.count,
            totalItems: lineItems.count,
            assignedItems: assigned
        )
    }
}

// MARK: - DTOs

struct SplitDetails {
    var subtotal: Double
    var tax: Double
    var tip: Double
    var discount: Double
    var total: Double

    var formattedSubtotal: String { String(format: "$%.2f", subtotal) }
    var formattedTax:      String { String(format: "$%.2f", tax) }
    var formattedTip:      String { String(format: "$%.2f", tip) }
    var formattedDiscount: String { String(format: "$%.2f", discount) }
    var formattedTotal:    String { String(format: "$%.2f", total) }
}

struct SplitSummary {
    var totalPeople: Int
    var totalItems: Int
    var assignedItems: Int

    var unassignedItems: Int { totalItems - assignedItems }
    var isComplete: Bool { assignedItems == totalItems && totalItems > 0 }
}
