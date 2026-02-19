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

    // Many-to-many: multiple people can share a single item (equal split)
    @Relationship(deleteRule: .nullify) var assignedPeople: [Person] = []

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
}
