//
//  Split.swift
//  CheckMate
//
//  Created by Syam Shukla on 2/18/26.
//

import Foundation
import SwiftData

@Model
final class Split {
    var receipt: Receipt?
    var person: Person?
    var amountOwed: Double
    var itemsSubtotal: Double
    var taxAmount: Double
    var tipAmount: Double
    var discountAmount: Double

    init(
        receipt: Receipt? = nil,
        person: Person? = nil,
        amountOwed: Double = 0.0,
        itemsSubtotal: Double = 0.0,
        taxAmount: Double = 0.0,
        tipAmount: Double = 0.0,
        discountAmount: Double = 0.0
    ) {
        self.receipt = receipt
        self.person = person
        self.amountOwed = amountOwed
        self.itemsSubtotal = itemsSubtotal
        self.taxAmount = taxAmount
        self.tipAmount = tipAmount
        self.discountAmount = discountAmount
    }
}
