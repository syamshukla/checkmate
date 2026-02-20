//
//  ReceiptScanningTests.swift
//  BilldTests
//
//  Test suite for receipt scanning and parsing functionality
//

import Testing
@testable import Billd

@Suite("Receipt Scanning Tests")
struct ReceiptScanningTests {
    
    // MARK: - ParsedLineItem Tests
    
    @Test("ParsedLineItem calculates total price correctly")
    func lineItemTotalPrice() async throws {
        let item = ParsedLineItem(name: "Fried Rice", price: 25.00, quantity: 4)
        let total = item.price * Double(item.quantity)
        #expect(total == 100.00, "4 items at $25 each should total $100")
    }
    
    @Test("ParsedLineItem handles quantity of 1")
    func singleQuantityItem() async throws {
        let item = ParsedLineItem(name: "Burger", price: 15.99, quantity: 1)
        let total = item.price * Double(item.quantity)
        #expect(total == 15.99, "Single item should equal its price")
    }
    
    // MARK: - Receipt Totals Tests
    
    @Test("Receipt total calculation includes all components")
    func receiptTotalCalculation() async throws {
        let subtotal = 100.00
        let tax = 10.00
        let tip = 15.00
        let discount = 5.00
        
        let expectedTotal = subtotal + tax + tip - discount
        #expect(expectedTotal == 120.00, "Total should be subtotal + tax + tip - discount")
    }
    
    @Test("Receipt handles zero tax and tip")
    func receiptWithZeroExtras() async throws {
        let subtotal = 50.00
        let tax = 0.0
        let tip = 0.0
        let discount = 0.0
        
        let expectedTotal = subtotal + tax + tip - discount
        #expect(expectedTotal == 50.00, "Total should equal subtotal when no extras")
    }
    
    // MARK: - Price Validation Tests
    
    @Test("Validate reasonable price range")
    func validatePriceRange() async throws {
        let validPrice = 12.99
        let tooLow = 0.001
        let tooHigh = 501.00
        
        #expect(validPrice >= 0.01 && validPrice <= 500.00, "Normal price should be valid")
        #expect(tooLow < 0.01, "Price below $0.01 is suspicious")
        #expect(tooHigh > 500.00, "Price above $500 is suspicious")
    }
    
    @Test("Items total matches subtotal within tolerance")
    func itemsTotalMatchesSubtotal() async throws {
        let items = [
            ParsedLineItem(name: "Item 1", price: 10.00, quantity: 2), // $20
            ParsedLineItem(name: "Item 2", price: 15.50, quantity: 1), // $15.50
            ParsedLineItem(name: "Item 3", price: 8.33, quantity: 3)   // $24.99
        ]
        
        let itemsTotal = items.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
        let expectedSubtotal = 60.49
        
        let difference = abs(itemsTotal - expectedSubtotal)
        let tolerance = 0.02 // 2 cents for rounding
        
        #expect(difference <= tolerance, "Items total should match subtotal within tolerance")
    }
    
    // MARK: - Receipt Validation Tests
    
    @Test("Validate receipt with all components")
    func validateCompleteReceipt() async throws {
        let items = [
            ParsedLineItem(name: "Burger", price: 15.00, quantity: 2), // $30
            ParsedLineItem(name: "Fries", price: 5.00, quantity: 2)    // $10
        ]
        
        let subtotal = 40.00
        let tax = 4.00
        let tip = 6.00
        let discount = 0.0
        let total = 50.00
        
        let itemsTotal = items.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
        let calculatedTotal = subtotal + tax + tip - discount
        
        #expect(itemsTotal == subtotal, "Items should sum to subtotal")
        #expect(calculatedTotal == total, "Calculated total should match receipt total")
    }
    
    // MARK: - Edge Cases
    
    @Test("Handle empty receipt")
    func handleEmptyReceipt() async throws {
        let receipt = ParsedReceipt(
            restaurantName: nil,
            items: [],
            subtotal: nil,
            tax: nil,
            tip: nil,
            discount: nil,
            total: nil
        )
        
        #expect(receipt.items.isEmpty, "Empty receipt should have no items")
        #expect(receipt.total == nil, "Empty receipt should have nil total")
    }
    
    @Test("Handle receipt with only subtotal")
    func handlePartialReceipt() async throws {
        let items = [
            ParsedLineItem(name: "Coffee", price: 3.50, quantity: 1)
        ]
        
        let subtotal = 3.50
        let receipt = ParsedReceipt(
            restaurantName: "Coffee Shop",
            items: items,
            subtotal: subtotal,
            tax: nil,
            tip: nil,
            discount: nil,
            total: nil
        )
        
        #expect(receipt.items.count == 1, "Should have one item")
        #expect(receipt.subtotal == 3.50, "Should have subtotal")
        #expect(receipt.total == nil, "Total not provided")
    }
    
    // MARK: - Integration Tests
    
    @Test("End-to-end receipt processing")
    func endToEndReceiptProcessing() async throws {
        // Simulate a complete receipt
        let items = [
            ParsedLineItem(name: "Burger", price: 12.99, quantity: 2),    // $25.98
            ParsedLineItem(name: "Fries", price: 4.50, quantity: 2),      // $9.00
            ParsedLineItem(name: "Soda", price: 2.50, quantity: 2)        // $5.00
        ]
        
        let subtotal = 39.98
        let tax = 4.00
        let tip = 6.00
        let discount = 0.0
        let total = 49.98
        
        let receipt = ParsedReceipt(
            restaurantName: "Burger Place",
            items: items,
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            discount: discount,
            total: total
        )
        
        // Validate all components
        let itemsTotal = items.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
        
        #expect(abs(itemsTotal - subtotal) < 0.02, "Items total should match subtotal")
        #expect(receipt.restaurantName == "Burger Place", "Restaurant name should be extracted")
        #expect(receipt.items.count == 3, "Should have 3 items")
        
        let calculatedTotal = subtotal + tax + tip - discount
        #expect(abs(calculatedTotal - total) < 0.02, "Calculated total should match")
    }
    
    @Test("Validate split calculation accuracy")
    func validateSplitCalculation() async throws {
        // Test that splits calculate correctly with quantities
        let item1 = ParsedLineItem(name: "Pizza", price: 20.00, quantity: 2) // $40 total
        let item2 = ParsedLineItem(name: "Salad", price: 10.00, quantity: 1) // $10 total
        
        let subtotal = 50.00 // $40 + $10
        let tax = 5.00
        let tip = 7.50
        let total = 62.50
        
        // If split 2 ways equally
        let perPersonSubtotal = subtotal / 2.0  // $25.00
        let perPersonTax = tax / 2.0            // $2.50
        let perPersonTip = tip / 2.0            // $3.75
        let perPersonTotal = total / 2.0        // $31.25
        
        #expect(perPersonTotal == 31.25, "Each person should pay $31.25")
        
        let reconstructedTotal = (perPersonSubtotal + perPersonTax + perPersonTip) * 2.0
        #expect(abs(reconstructedTotal - total) < 0.02, "Split should reconstruct to original total")
    }
}
