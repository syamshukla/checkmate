//
//  OCRService.swift
//  Billd
//
//  Created by Syam Shukla on 2/18/26.
//

import UIKit
import Vision
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ParsedLineItem {
    var name: String
    var price: Double
}

struct ParsedReceipt {
    var restaurantName: String?
    var items: [ParsedLineItem]
    var subtotal: Double?
    var tax: Double?
    var tip: Double?
    var discount: Double?
    var total: Double?
}

class OCRService {
    static let shared = OCRService()
    private init() {}
    
    // Check if Apple Intelligence is available
    @available(iOS 26.0, *)
    private var model: SystemLanguageModel {
        SystemLanguageModel.default
    }
    
    private var useAI: Bool {
        if #available(iOS 26.0, *) {
            if case .available = model.availability {
                return true
            }
        }
        return false
    }

    // MARK: - Public

    func extractReceiptData(from image: UIImage) async -> ParsedReceipt {
        guard let cgImage = image.cgImage else { 
            return ParsedReceipt(restaurantName: nil, items: [], subtotal: nil, tax: nil, tip: nil, discount: nil, total: nil)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        var rawLines: [String] = []

        let request = VNRecognizeTextRequest { req, _ in
            guard let results = req.results as? [VNRecognizedTextObservation] else { return }
            
            // Sort by Y position (top to bottom) for better ordering
            let sorted = results.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            
            for obs in sorted {
                if let top = obs.topCandidates(1).first {
                    rawLines.append(top.string)
                }
            }
        }
        
        // Use FAST recognition level - better for receipts with tables
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        
        // Enable automatic language detection
        request.automaticallyDetectsLanguage = true
        
        // Use revision3 for better accuracy (iOS 16+)
        if #available(iOS 16.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }

        do {
            try handler.perform([request])
        } catch {
            print("OCR Error: \(error)")
            return ParsedReceipt(restaurantName: nil, items: [], subtotal: nil, tax: nil, tip: nil, discount: nil, total: nil)
        }

        // Try AI-powered parsing first if available
        if useAI {
            let aiReceipt = await parseReceiptWithAI(from: rawLines)
            if !aiReceipt.items.isEmpty {
                print("✨ AI extracted: \(aiReceipt.items.count) items, restaurant: \(aiReceipt.restaurantName ?? "unknown")")
                return aiReceipt
            }
        }
        
        // Fallback to regex-based parsing
        let items = parseLineItems(from: rawLines)
        let receipt = ParsedReceipt(
            restaurantName: extractRestaurantName(from: rawLines),
            items: items,
            subtotal: extractAmount(from: rawLines, keywords: ["subtotal", "sub total", "sub-total"]),
            tax: extractAmount(from: rawLines, keywords: ["tax", "sales tax", "hst", "gst"]),
            tip: extractAmount(from: rawLines, keywords: ["tip", "gratuity"]),
            discount: extractAmount(from: rawLines, keywords: ["discount", "promo", "coupon"]),
            total: extractAmount(from: rawLines, keywords: ["total", "amount due", "balance"])
        )
        print("📝 Regex extracted: \(items.count) items, restaurant: \(receipt.restaurantName ?? "unknown")")
        return receipt
    }
    
    // Legacy method for backward compatibility
    func extractLineItems(from image: UIImage) async -> [ParsedLineItem] {
        let receipt = await extractReceiptData(from: image)
        return receipt.items
    }
    
    // MARK: - AI-Powered Parsing (Apple Intelligence)
    
    @available(iOS 26.0, *)
    @Generable(description: "Complete receipt information including restaurant, items, and totals")
    struct ReceiptData {
        @Guide(description: "The restaurant or business name, typically at the top of the receipt. Extract only if clearly identifiable. Return empty string if unclear.")
        var restaurantName: String
        
        @Guide(description: "All food and drink items from the receipt with their prices. Include every item purchased, cleaned up without quantity prefixes.")
        var items: [ReceiptLineItem]
        
        @Guide(description: "Subtotal amount before tax and tip, if shown on receipt", .range(0.01...10000.0))
        var subtotal: Double?
        
        @Guide(description: "Tax amount, if shown on receipt", .range(0.00...10000.0))
        var tax: Double?
        
        @Guide(description: "Tip or gratuity amount, if shown on receipt", .range(0.00...10000.0))
        var tip: Double?
        
        @Guide(description: "Any discounts or promotional deductions, if shown on receipt", .range(0.00...10000.0))
        var discount: Double?
        
        @Guide(description: "Final total amount, if shown on receipt", .range(0.01...10000.0))
        var total: Double?
    }
    
    @available(iOS 26.0, *)
    @Generable(description: "A single item from a receipt")
    struct ReceiptLineItem {
        @Guide(description: "The name of the food or drink item, cleaned up and without quantity prefixes like '2x'")
        var name: String
        
        @Guide(description: "The price of the item in dollars", .range(0.01...1000.0))
        var price: Double
    }
    
    private func parseReceiptWithAI(from lines: [String]) async -> ParsedReceipt {
        if #available(iOS 26.0, *) {
            return await _parseReceiptWithAI(from: lines)
        } else {
            return ParsedReceipt(restaurantName: nil, items: [], subtotal: nil, tax: nil, tip: nil, discount: nil, total: nil)
        }
    }
    
    @available(iOS 26.0, *)
    private func _parseReceiptWithAI(from lines: [String]) async -> ParsedReceipt {
        let fullText = lines.joined(separator: "\n")
        
        let instructions = """
        You are a receipt parser. Extract ALL information from the receipt accurately.
        
        What to extract:
        - Restaurant name: ONLY if clearly visible at top of receipt (like "McDonald's", "Olive Garden"). If unclear or looks like an address/location, return empty string.
        - ALL food and drink items with their individual prices
        - Subtotal (amount before tax and tip)
        - Tax amount
        - Tip/gratuity amount
        - Any discounts or promotions
        - Final total amount
        
        What to ignore:
        - Addresses, phone numbers, website URLs
        - Payment method details (card numbers, transaction IDs)
        - Date and time stamps
        - Server/cashier names
        - Order numbers
        
        Rules for items:
        - Include EVERY purchased item with its price
        - Clean up item names (remove "1x", "2x" quantity prefixes)
        - Remove extra dots, dashes, asterisks
        - If an item appears multiple times, include each occurrence separately
        
        Rules for restaurant name:
        - Must be a clear business/restaurant name
        - Should appear near the top of receipt
        - If uncertain or if it looks like an address, return empty string
        - Examples of GOOD names: "Starbucks", "Chipotle", "Joe's Pizza"
        - Examples of BAD (return empty): "123 Main St", "Store #4521", unclear text
        """
        
        let session = LanguageModelSession(instructions: instructions)
        
        do {
            let response = try await session.respond(
                to: "Extract all information from this receipt:\n\n\(fullText)",
                generating: ReceiptData.self
            )
            
            let data = response.content
            
            // Only use restaurant name if it's meaningful (not empty or just whitespace)
            let restaurantName = data.restaurantName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            return ParsedReceipt(
                restaurantName: restaurantName.isEmpty ? nil : restaurantName,
                items: data.items.map { ParsedLineItem(name: $0.name, price: $0.price) },
                subtotal: data.subtotal,
                tax: data.tax,
                tip: data.tip,
                discount: data.discount,
                total: data.total
            )
        } catch {
            print("AI parsing failed: \(error)")
            return ParsedReceipt(restaurantName: nil, items: [], subtotal: nil, tax: nil, tip: nil, discount: nil, total: nil)
        }
    }

    // MARK: - Parsing

    private func parseLineItems(from lines: [String]) -> [ParsedLineItem] {
        var items: [ParsedLineItem] = []

        // --- Pass 1: same-line match (most receipts) ---
        // Handles: "Burger         12.99"
        //          "Burger ......  $12.99"
        //          "2x Burger       25.98"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !isNoise(trimmed) else { continue }

            if let item = parseSameLine(trimmed) {
                items.append(item)
            }
        }

        // --- Pass 2: adjacent-line match (some receipt formats) ---
        // Handles two-line format:
        //   "Grilled Salmon"
        //   "24.99"
        if items.isEmpty {
            items = parseAdjacentLines(lines)
        }

        return deduplicate(items)
    }

    /// Parses a single line that contains both a name and a price.
    /// Handles multiple separator styles and optional currency symbols.
    private func parseSameLine(_ line: String) -> ParsedLineItem? {
        // Regex: capture everything before the last price-like token
        // Price = optional $ then digits . two-digits, optionally preceded by spaces/dots/dashes
        let pattern = #"^(.+?)\s*[\s.\-·]+\$?\s*(\d{1,4}[.,]\d{2})\s*$"#

        if let item = matchItem(line: line, pattern: pattern) {
            return item
        }

        // Simpler fallback: anything ending in a price
        let fallback = #"^(.+?)\s{2,}\$?\s*(\d{1,4}[.,]\d{2})\s*$"#
        return matchItem(line: line, pattern: fallback)
    }

    private func matchItem(line: String, pattern: String) -> ParsedLineItem? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 3,
              let nameRange  = Range(match.range(at: 1), in: line),
              let priceRange = Range(match.range(at: 2), in: line)
        else { return nil }

        let name  = String(line[nameRange])
            .trimmingCharacters(in: .init(charactersIn: ".-· \t"))
        let priceStr = String(line[priceRange])
            .replacingOccurrences(of: ",", with: ".")

        guard !name.isEmpty,
              name.count > 1,
              let price = Double(priceStr),
              price > 0,
              price < 5000            // sanity upper bound
        else { return nil }

        // Skip quantity-only lines like "1 x 2" or "2"
        if name.allSatisfy({ $0.isNumber || $0 == "x" || $0 == " " }) { return nil }

        return ParsedLineItem(name: cleanName(name), price: price)
    }

    /// Two-pass adjacent-line parse: name line followed by a price-only line.
    private func parseAdjacentLines(_ lines: [String]) -> [ParsedLineItem] {
        var items: [ParsedLineItem] = []
        let priceOnly = #"^\$?\s*(\d{1,4}[.,]\d{2})\s*$"#
        guard let priceRegex = try? NSRegularExpression(pattern: priceOnly) else { return [] }

        var i = 0
        while i < lines.count - 1 {
            let current = lines[i].trimmingCharacters(in: .whitespaces)
            let next    = lines[i + 1].trimmingCharacters(in: .whitespaces)

            if !isNoise(current), current.count > 2,
               let m = priceRegex.firstMatch(in: next, range: NSRange(next.startIndex..., in: next)),
               let r = Range(m.range(at: 1), in: next),
               let price = Double(String(next[r]).replacingOccurrences(of: ",", with: ".")),
               price > 0, price < 5000 {
                items.append(ParsedLineItem(name: cleanName(current), price: price))
                i += 2
                continue
            }
            i += 1
        }
        return items
    }

    // MARK: - Filters & cleanup
    
    /// Extract restaurant name from the first few lines (typically at top)
    private func extractRestaurantName(from lines: [String]) -> String? {
        // Check first 5 lines for a likely restaurant name
        let candidates = lines.prefix(5)
        for line in candidates {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip if too short or looks like an address/number
            guard trimmed.count >= 3,
                  trimmed.count <= 40,
                  !trimmed.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }),
                  !trimmed.contains("www."),
                  !trimmed.contains("http"),
                  !trimmed.lowercased().contains("receipt"),
                  !trimmed.lowercased().contains("invoice")
            else { continue }
            
            // If it contains mostly letters and spaces, likely a name
            let letterCount = trimmed.filter { $0.isLetter || $0 == " " || $0 == "'" || $0 == "&" }.count
            if Double(letterCount) / Double(trimmed.count) > 0.7 {
                return trimmed
            }
        }
        return nil
    }
    
    /// Extract a specific amount from lines using keywords
    private func extractAmount(from lines: [String], keywords: [String]) -> Double? {
        for line in lines {
            let lower = line.lowercased()
            
            // Check if line contains any of the keywords
            guard keywords.contains(where: { lower.contains($0) }) else { continue }
            
            // Try to extract a price from this line
            let pattern = #"\$?\s*(\d{1,6}[.,]\d{2})"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range(at: 1), in: line) {
                let priceStr = String(line[range]).replacingOccurrences(of: ",", with: ".")
                return Double(priceStr)
            }
        }
        return nil
    }

    /// Returns true for lines that are definitely not item lines.
    private func isNoise(_ line: String) -> Bool {
        let lower = line.lowercased()

        // Very short lines are noise
        if line.count < 3 { return true }

        // Lines that are purely numeric (page numbers, order numbers, etc.)
        if line.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "/" }) { return true }

        // Common receipt boilerplate
        let boilerplate = [
            "thank you", "have a nice", "come again", "visit us",
            "www.", "http", "tel:", "phone:", "fax:",
            "subtotal", "sub total", "sub-total",
            "total", "tax", "tip", "change", "balance", "due",
            "visa", "mastercard", "amex", "cash", "credit", "debit",
            "order #", "table #", "server:", "cashier:",
            "transaction", "approval", "auth",
            "open:", "close:", "hours",
            "address", "suite", "floor",
        ]
        if boilerplate.contains(where: { lower.contains($0) }) { return true }

        return false
    }

    private func cleanName(_ raw: String) -> String {
        var name = raw
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: .init(charactersIn: ".-·*#@"))

        // Collapse internal runs of dots/dashes used as separators
        if let r = try? NSRegularExpression(pattern: #"[\.\-·]{3,}"#) {
            name = r.stringByReplacingMatches(
                in: name,
                range: NSRange(name.startIndex..., in: name),
                withTemplate: " "
            ).trimmingCharacters(in: .whitespaces)
        }

        // Strip leading quantity "2x " or "2 x "
        if let r = try? NSRegularExpression(pattern: #"^\d+\s*[xX]\s+"#) {
            name = r.stringByReplacingMatches(
                in: name,
                range: NSRange(name.startIndex..., in: name),
                withTemplate: ""
            )
        }

        // Capitalize first letter
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private func deduplicate(_ items: [ParsedLineItem]) -> [ParsedLineItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.name.lowercased()).inserted }
    }
}
