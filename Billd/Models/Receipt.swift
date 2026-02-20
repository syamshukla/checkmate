//
//  Receipt.swift
//  CheckMate
//
//  Created by Syam Shukla on 2/18/26.
//

import Foundation
import SwiftData

@Model
final class Receipt {
    var date: Date
    var restaurantName: String
    var subtotal: Double
    var tax: Double
    var tip: Double
    var discount: Double
    var total: Double

    @Relationship(deleteRule: .cascade, inverse: \LineItem.receipt) var lineItems: [LineItem] = []
    @Relationship(deleteRule: .cascade, inverse: \Split.receipt) var splits: [Split] = []

    init(
        date: Date = Date(),
        restaurantName: String,
        subtotal: Double,
        tax: Double = 0,
        tip: Double = 0,
        discount: Double = 0
    ) {
        self.date = date
        self.restaurantName = restaurantName
        self.subtotal = subtotal
        self.tax = tax
        self.tip = tip
        self.discount = discount
        self.total = subtotal + tax + tip - discount
    }

    func updateTotal() {
        total = subtotal + tax + tip - discount
    }
}
