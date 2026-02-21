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
    var quantity: Int = 1
}

struct ParsedReceipt {
    var restaurantName: String?
    var items: [ParsedLineItem]
    var subtotal: Double?
    var tax: Double?
    var tip: Double?
    var discount: Double?
    var total: Double?
    var confidence: Double = 0.0  // 0.0 - 1.0
    var parsingMethod: ParsingMethod = .spatial

    enum ParsingMethod {
        case spatial
        case appleAI
        case cloudAI
    }
}

// MARK: - Spatial OCR Structures

/// A single text observation from Vision with its bounding box position
private struct TextObservation {
    let text: String
    let bounds: CGRect  // Normalized coordinates, bottom-left origin (Vision default)
    let confidence: Float

    /// Center Y in Vision coordinates (higher = top of image)
    var midY: CGFloat { bounds.midY }
    var midX: CGFloat { bounds.midX }
    var minX: CGFloat { bounds.minX }
    var maxX: CGFloat { bounds.maxX }
    var height: CGFloat { bounds.height }
}

/// A group of observations that sit on the same horizontal line of the receipt
private struct TextRow {
    var observations: [TextObservation]
    /// Y of the first observation added — used as a stable anchor for row membership.
    /// Using a rolling average caused drift: each added observation nudged the average
    /// toward the next row, eventually pulling in observations that belong below.
    let anchorY: CGFloat

    init(firstObservation: TextObservation) {
        self.observations = [firstObservation]
        self.anchorY = firstObservation.midY
    }

    /// Observations sorted left-to-right
    var sortedLeftToRight: [TextObservation] {
        observations.sorted { $0.minX < $1.minX }
    }

    /// Full text of the row, reading left-to-right
    var fullText: String {
        sortedLeftToRight.map { $0.text }.joined(separator: " ")
    }
}

class OCRService {
    static let shared = OCRService()
    private init() {}

    // User settings for parsing strategy
    var enableCloudFallback = false  // Set to true to use free Gemini API
    var geminiAPIKey: String? = nil  // Optional: Get free key from ai.google.dev

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
        print("📸 Preprocessing image for OCR...")
        // Perspective-correct first so that row Y-coordinates are accurate,
        // then apply contrast enhancement.
        let correctedImage = await ImagePreprocessor.shared.correctPerspective(image)
        let enhancedImage = ImagePreprocessor.shared.enhanceForOCR(correctedImage)

        guard let cgImage = enhancedImage.cgImage else {
            return ParsedReceipt(restaurantName: nil, items: [], subtotal: nil, tax: nil, tip: nil, discount: nil, total: nil)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        var observations: [TextObservation] = []

        let request = VNRecognizeTextRequest { req, _ in
            guard let results = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in results {
                if let top = obs.topCandidates(1).first {
                    observations.append(TextObservation(
                        text: top.string,
                        bounds: obs.boundingBox,
                        confidence: top.confidence
                    ))
                }
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true

        do {
            try handler.perform([request])
            print("📝 OCR extracted \(observations.count) text observations")

            // Debug: print raw observations with positions
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📄 Raw OCR Observations (with positions):")
            for (index, obs) in observations.enumerated() {
                print("  \(String(format: "%2d", index)): '\(obs.text)' x:\(String(format: "%.3f", obs.minX))...\(String(format: "%.3f", obs.maxX)) y:\(String(format: "%.3f", obs.midY))")
            }
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        } catch {
            print("OCR Error: \(error)")
            return ParsedReceipt(restaurantName: nil, items: [], subtotal: nil, tax: nil, tip: nil, discount: nil, total: nil)
        }

        // Group observations into spatial rows
        let rows = groupIntoRows(observations)
        let rawLines = rows.map { $0.fullText }

        print("📋 Grouped into \(rows.count) rows:")
        for (index, row) in rows.enumerated() {
            print("  Row \(String(format: "%2d", index)): '\(row.fullText)' (\(row.observations.count) obs)")
        }

        // HYBRID APPROACH: Try methods in order of preference

        // Try 1: AI-powered parsing (Apple Intelligence)
        if useAI {
            let aiReceipt = await parseReceiptWithAI(from: rawLines)
            if aiReceipt.confidence >= 0.7 {
                print("✅ Using Apple AI result (confidence: \(String(format: "%.1f%%", aiReceipt.confidence * 100)))")
                return aiReceipt
            } else {
                print("⚠️ Apple AI confidence too low (\(String(format: "%.1f%%", aiReceipt.confidence * 100)))")
            }
        }

        // Try 2: Cloud AI fallback (Gemini - free tier, multimodal)
        if enableCloudFallback, let apiKey = geminiAPIKey {
            print("🌐 Trying cloud AI fallback (multimodal)...")
            let cloudReceipt = await parseReceiptWithGemini(image: image, from: rawLines, apiKey: apiKey)
            if cloudReceipt.confidence >= 0.7 {
                print("✅ Using Cloud AI result (confidence: \(String(format: "%.1f%%", cloudReceipt.confidence * 100)))")
                return cloudReceipt
            }
        }

        // Try 3: Spatial parsing (uses bounding box positions)
        print("📐 Using spatial parsing")
        return parseReceiptSpatially(from: rows)
    }

    // Legacy method for backward compatibility
    func extractLineItems(from image: UIImage) async -> [ParsedLineItem] {
        let receipt = await extractReceiptData(from: image)
        return receipt.items
    }

    // MARK: - Spatial Row Grouping

    /// Groups individual text observations into rows based on their vertical position.
    /// Observations on the same horizontal line of the receipt share similar Y coordinates.
    private func groupIntoRows(_ observations: [TextObservation]) -> [TextRow] {
        guard !observations.isEmpty else { return [] }

        // Sort top-to-bottom (higher midY = top of receipt in Vision coordinates)
        let sorted = observations.sorted { $0.midY > $1.midY }

        // Dynamic threshold: based on average text height so it adapts to any receipt
        let avgHeight = sorted.reduce(CGFloat(0)) { $0 + $1.height } / CGFloat(sorted.count)
        let threshold = max(avgHeight * 0.6, 0.005)

        var rows: [TextRow] = []
        var currentRow = TextRow(firstObservation: sorted[0])

        for i in 1..<sorted.count {
            let obs = sorted[i]
            // Compare against the row's anchor Y (first observation), not a rolling
            // average. The rolling average drifts as observations are added, which can
            // pull a price from the row below into the current row.
            if abs(obs.midY - currentRow.anchorY) <= threshold {
                currentRow.observations.append(obs)
            } else {
                rows.append(currentRow)
                currentRow = TextRow(firstObservation: obs)
            }
        }
        rows.append(currentRow)

        return rows
    }

    // MARK: - Spatial Receipt Parsing

    /// Main spatial parser: classifies rows into receipt sections, then extracts data from each.
    private func parseReceiptSpatially(from rows: [TextRow]) -> ParsedReceipt {
        // Phase 1: Classify rows into sections (header / items / totals)
        var headerRows: [TextRow] = []
        var itemRows: [TextRow] = []
        var totalsRows: [TextRow] = []
        var inTotalsSection = false
        var firstItemFound = false

        for row in rows {
            let text = row.fullText
            let lower = text.lowercased().trimmingCharacters(in: .whitespaces)

            if isNoise(text) { continue }

            // Skip visual separators — they appear everywhere (between item categories,
            // before and after totals, etc.) so they are NOT reliable section markers.
            if isSeparatorLine(text) { continue }

            // Totals keywords (subtotal, tax, total, tip, etc.)
            if isTotalsKeyword(lower) {
                inTotalsSection = true
                totalsRows.append(row)
                continue
            }

            if inTotalsSection {
                totalsRows.append(row)
                continue
            }

            // Check if this row contains a price
            let hasPrice = findPriceInRow(row) != nil

            // Before we've found the first item, rows without prices are header
            if !firstItemFound && !hasPrice {
                headerRows.append(row)
                continue
            }

            // Row with a price that isn't a totals line → item
            if hasPrice {
                firstItemFound = true
                itemRows.append(row)
            } else if firstItemFound {
                // No-price row in the items zone — may be an item name for the next priced row
                // (e.g. multi-line "House fried rice / Spicy chicken / [price]" style receipts)
                itemRows.append(row)
            }
        }

        print("📊 Receipt sections: \(headerRows.count) header, \(itemRows.count) items, \(totalsRows.count) totals")

        // Phase 2: Extract structured data from each section
        let restaurantName = extractRestaurantNameFromHeader(headerRows)
        let totals = extractTotalsFromRows(totalsRows)

        // Agentic strategy: run spatial parsing first, then validate against the printed
        // subtotal. If the spatial result is off by more than 20%, retry with flat
        // text-line parsing (the same text a human would see if they copy-pasted the receipt).
        // Pick whichever strategy produces totals closer to the printed subtotal.
        var items = extractItemsFromRows(itemRows)
        if let subtotal = totals.subtotal, subtotal > 0, !itemRows.isEmpty {
            let spatialTotal = items.reduce(0.0) { $0 + $1.price * Double($1.quantity) }
            let spatialDiff  = abs(spatialTotal - subtotal) / subtotal
            if spatialDiff > 0.20 {
                let flatItems = parseItemsFlatFromRows(itemRows)
                if !flatItems.isEmpty {
                    let flatTotal = flatItems.reduce(0.0) { $0 + $1.price * Double($1.quantity) }
                    let flatDiff  = abs(flatTotal - subtotal) / subtotal
                    if flatDiff < spatialDiff {
                        print("📐 Flat-line parsing preferred (spatial Δ \(Int(spatialDiff*100))% → flat Δ \(Int(flatDiff*100))%)")
                        items = flatItems
                    } else {
                        print("📐 Keeping spatial result (spatial Δ \(Int(spatialDiff*100))% ≤ flat Δ \(Int(flatDiff*100))%)")
                    }
                }
            }
        }

        var receipt = ParsedReceipt(
            restaurantName: restaurantName,
            items: items,
            subtotal: totals.subtotal,
            tax: totals.tax,
            tip: totals.tip,
            discount: totals.discount,
            total: totals.total
        )
        receipt.parsingMethod = .spatial
        receipt.confidence = calculateConfidence(for: receipt)

        // Validation logging
        if !items.isEmpty {
            let itemsTotal = items.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
            print("🔍 Spatial Extraction Validation:")
            print("  Items total: $\(String(format: "%.2f", itemsTotal))")
            if let subtotal = totals.subtotal {
                print("  Subtotal: $\(String(format: "%.2f", subtotal))")
                print("  Difference: $\(String(format: "%.2f", abs(itemsTotal - subtotal)))")
            }
            for item in items {
                let lineTotal = item.price * Double(item.quantity)
                print("  📦 \(item.quantity)x \(item.name) @ $\(String(format: "%.2f", item.price)) = $\(String(format: "%.2f", lineTotal))")
            }
        }

        print("📐 Spatial extracted: \(items.count) items, confidence: \(String(format: "%.1f%%", receipt.confidence * 100))")

        return receipt
    }

    // MARK: - Item Extraction (Spatial)

    /// Extracts line items from rows classified as belonging to the items section.
    ///
    /// Uses a stateful "pending name" strategy to handle multi-line receipt formats
    /// where the item name appears on its own row above the price row, e.g.:
    ///
    ///   House Fried Rice          ← name-only row → becomes pendingName
    ///     extra crispy ......30$  ← price row     → item created using pendingName
    ///
    /// A no-price row becomes a pendingName whenever:
    ///   • No pending name is already set (first candidate wins), AND
    ///   • The text looks like an item name (not a modifier/descriptor).
    ///
    /// This replaces the old "!lastRowHadPrice" guard which silently dropped item names
    /// that appeared immediately after a priced row — a very common receipt layout.
    private func extractItemsFromRows(_ rows: [TextRow]) -> [ParsedLineItem] {
        var items: [ParsedLineItem] = []
        var pendingName: String? = nil  // Name-only row waiting for the next price row

        for row in rows {
            let price = findPriceInRow(row)

            if let price = price {
                if let pending = pendingName {
                    // A name-only row preceded this price row.
                    // First try to extract an inline name from the price row itself.
                    // If that inline name is a real item name (not a modifier/descriptor),
                    // it wins — the pending row was a section header or unrelated text.
                    // If the inline parse fails or its name looks like a modifier (e.g.
                    // "extra crispy"), fall back to the pending name.
                    let inlineItem = parseItemFromRow(row)
                    let inlineNameIsGood = inlineItem.map { !isModifierLine($0.name) } ?? false

                    if inlineNameIsGood, let item = inlineItem {
                        items.append(item)
                        print("  📦 Inline (discarded pending '\(pending)'): \(item.name) @ $\(String(format: "%.2f", item.price))")
                    } else if !isTotalsKeyword(pending.lowercased()) {
                        let (name, quantity) = extractQuantityAndName(from: pending)
                        let unitPrice = price / Double(quantity)
                        if !name.isEmpty, name.count > 1, unitPrice > 0, unitPrice < 1000 {
                            let item = ParsedLineItem(name: cleanName(name), price: unitPrice, quantity: quantity)
                            items.append(item)
                            print("  📦 Pending-name: '\(pending)' + $\(String(format: "%.2f", price)) → \(quantity)x \(item.name)")
                        }
                    }
                    pendingName = nil
                } else {
                    // No pending name — name and price are on the same row (standard format)
                    if let item = parseItemFromRow(row) {
                        items.append(item)
                    }
                }

            } else {
                // No price on this row — could be an item name for the next priced row.
                // Set as pendingName if:
                //   • No pending name is already waiting (first candidate wins), AND
                //   • The text looks like an item name, not a modifier/descriptor.
                let text = row.fullText.trimmingCharacters(in: .whitespaces)
                if pendingName == nil,
                   !isNoise(text), !isTotalsKeyword(text.lowercased()), text.count > 1,
                   !isModifierLine(text) {
                    pendingName = text
                    print("  🏷️ Pending name set: '\(text)'")
                }
            }
        }

        // Adjacent-line fallback if stateful parsing found nothing
        if items.isEmpty && rows.count >= 2 {
            let allText = rows.map { $0.fullText }
            items = parseAdjacentLines(allText)
        }

        return deduplicate(items)
    }

    /// Returns true if a no-price line looks like a modifier or descriptor rather than
    /// a new item name. Modifiers are typically:
    ///   • Parenthesized:  "(no onions)", "(add cheese)"
    ///   • All lowercase with no leading capital: "extra crispy", "well done"
    ///   • Very short single words:  "Large", "Sm"  — too ambiguous alone
    ///   • Leading whitespace (indented on the original receipt)
    ///   • Purely numeric or symbol-heavy
    private func isModifierLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Parenthesized text is always a modifier
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") { return true }

        // All lowercase multi-word → likely a descriptor, not an item name
        // e.g. "extra crispy", "well done", "no onions"
        if trimmed == trimmed.lowercased() && trimmed.contains(" ") { return true }

        // Multi-word ALL-CAPS → section header (APPETIZERS, COLD DRINKS, etc.)
        // Single-word all-caps (BURGER) could be a real item name so we require a space.
        let letters = trimmed.filter { $0.isLetter }
        if letters.count > 3, letters.allSatisfy({ $0.isUppercase }), trimmed.contains(" ") { return true }

        // Very short single token with no digits (e.g. size modifier "Lg", "Sm")
        if !trimmed.contains(" ") && trimmed.count <= 3 { return true }

        return false
    }

    /// Parses a single row into a line item using spatial and text analysis.
    private func parseItemFromRow(_ row: TextRow) -> ParsedLineItem? {
        let sorted = row.sortedLeftToRight

        // Strategy 1: Multiple observations — use spatial separation
        // (Vision split the name and price into separate text blocks)
        if sorted.count >= 2 {
            if let item = parseMultiObservationRow(sorted) {
                print("  📦 Spatial: '\(row.fullText)' → \(item.quantity)x \(item.name) @ $\(String(format: "%.2f", item.price))")
                return item
            }
        }

        // Strategy 2: Single observation — name and price in one text block
        if let item = parseCombinedLine(row.fullText) {
            print("  📦 Combined: '\(row.fullText)' → \(item.quantity)x \(item.name) @ $\(String(format: "%.2f", item.price))")
            return item
        }

        print("  ❌ Could not parse row: '\(row.fullText)'")
        return nil
    }

    /// Handles rows where Vision returned separate observations for name and price.
    /// Uses X-position to identify: leftmost = item name, rightmost number = price.
    private func parseMultiObservationRow(_ sorted: [TextObservation]) -> ParsedLineItem? {
        // Find the rightmost observation that looks like a standalone price
        var priceIndex: Int?
        var priceValue: Double?

        for i in stride(from: sorted.count - 1, through: 0, by: -1) {
            if let price = parseStandalonePrice(sorted[i].text) {
                priceIndex = i
                priceValue = price
                break
            }
        }

        guard let price = priceValue, let pIdx = priceIndex else { return nil }

        // Everything to the left of the price observation forms the item name
        let nameObservations = Array(sorted[0..<pIdx])
        guard !nameObservations.isEmpty else { return nil }

        let rawName = nameObservations.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !rawName.isEmpty else { return nil }

        // Skip if the name looks like a totals keyword
        if isTotalsKeyword(rawName.lowercased()) { return nil }

        let (name, quantity) = extractQuantityAndName(from: rawName)
        let unitPrice = price / Double(quantity)

        guard !name.isEmpty, name.count > 1,
              unitPrice > 0, unitPrice < 1000 else { return nil }

        // Skip purely numeric names
        if name.allSatisfy({ $0.isNumber || $0 == " " || $0 == "x" }) { return nil }

        return ParsedLineItem(name: cleanName(name), price: unitPrice, quantity: quantity)
    }

    /// Parses a single combined text string that contains both item name and price.
    /// Used when Vision merged the entire line into one observation.
    private func parseCombinedLine(_ text: String) -> ParsedLineItem? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 2 else { return nil }
        if isNoise(trimmed) || isTotalsKeyword(trimmed.lowercased()) { return nil }

        // Try patterns from most to least specific
        let patterns = [
            // "Burger ......... $12.99" (dot/dash separators)
            #"^(.+?)\s*[\s.\-·]{2,}\$?\s*(\d{1,4}[.,]\d{1,2})\s*$"#,
            // "Burger    12.99" (2+ spaces)
            #"^(.+?)\s{2,}\$?\s*(\d{1,4}[.,]\d{1,2})\s*$"#,
            // "Burger $12.99" (single space before $)
            #"^(.+?)\s+\$\s*(\d{1,4}[.,]\d{1,2})\s*$"#,
            // "Burger 12.99" (single space, no $)
            #"^(.+?)\s+(\d{1,4}[.,]\d{1,2})\s*$"#,
        ]

        for pattern in patterns {
            if let item = matchCombinedPattern(trimmed, pattern: pattern) {
                return item
            }
        }

        return nil
    }

    /// Helper to match a name+price pattern and return a ParsedLineItem.
    private func matchCombinedPattern(_ text: String, pattern: String) -> ParsedLineItem? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let nameRange = Range(match.range(at: 1), in: text),
              let priceRange = Range(match.range(at: 2), in: text)
        else { return nil }

        let rawName = String(text[nameRange])
            .trimmingCharacters(in: .init(charactersIn: ".-· \t"))
        let priceStr = String(text[priceRange])
            .replacingOccurrences(of: ",", with: ".")

        guard !rawName.isEmpty,
              rawName.count > 1,
              let totalPrice = Double(priceStr),
              totalPrice > 0,
              totalPrice < 5000
        else { return nil }

        // Skip quantity-only or purely numeric names
        if rawName.allSatisfy({ $0.isNumber || $0 == "x" || $0 == " " }) { return nil }

        let (name, quantity) = extractQuantityAndName(from: rawName)
        let unitPrice = totalPrice / Double(quantity)

        guard unitPrice >= 0.01, unitPrice <= 1000 else { return nil }

        return ParsedLineItem(name: cleanName(name), price: unitPrice, quantity: quantity)
    }

    /// Adjacent-line fallback: name on one line, price on the next.
    /// Handles receipt formats where item name and price are on separate lines.
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
                let (name, quantity) = extractQuantityAndName(from: current)
                let unitPrice = price / Double(quantity)
                items.append(ParsedLineItem(name: cleanName(name), price: unitPrice, quantity: quantity))
                i += 2
                continue
            }
            i += 1
        }
        return items
    }

    /// Flat-line fallback: parse each row's full text as a self-contained "name  price" string,
    /// exactly the way a human reads copy-pasted receipt text.
    /// Used by the agentic strategy selector when spatial parsing mismatches the subtotal.
    private func parseItemsFlatFromRows(_ rows: [TextRow]) -> [ParsedLineItem] {
        var items: [ParsedLineItem] = []
        let lines = rows.map { $0.fullText }

        // Pass 1: combined-line patterns on each row (name + price in one string)
        for line in lines {
            if let item = parseCombinedLine(line),
               !isTotalsKeyword(item.name.lowercased()) {
                items.append(item)
            }
        }

        // Pass 2: adjacent-line (name row then price-only row)
        if items.isEmpty {
            items = parseAdjacentLines(lines)
        }

        return deduplicate(items)
    }

    // MARK: - Price Parsing

    /// Parses a standalone price string like "$12.99", "12.99", "12,99".
    private func parseStandalonePrice(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)

        // Must be a standalone price (optionally with $ prefix)
        let pattern = #"^\$?\s*(\d{1,4}[.,]\d{1,2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let range = Range(match.range(at: 1), in: cleaned)
        else { return nil }

        let priceStr = String(cleaned[range]).replacingOccurrences(of: ",", with: ".")
        guard let price = Double(priceStr), price > 0, price < 10000 else { return nil }
        return price
    }

    /// Finds the price value in a row by checking observations then the combined text.
    private func findPriceInRow(_ row: TextRow) -> Double? {
        // Check rightmost observations for a standalone price
        for obs in row.sortedLeftToRight.reversed() {
            if let price = parseStandalonePrice(obs.text) {
                return price
            }
        }

        // Fall back: look for a price embedded in the full text
        let fullText = row.fullText
        let pattern = #"\$?\s*(\d{1,4}[.,]\d{1,2})"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: fullText, range: NSRange(fullText.startIndex..., in: fullText))
            if let lastMatch = matches.last,
               let range = Range(lastMatch.range(at: 1), in: fullText) {
                let priceStr = String(fullText[range]).replacingOccurrences(of: ",", with: ".")
                return Double(priceStr)
            }
        }

        return nil
    }

    // MARK: - Quantity Extraction

    /// Extracts a quantity prefix from the item name and returns (cleaned name, quantity).
    private func extractQuantityAndName(from text: String) -> (name: String, quantity: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // "2x Item" or "2X Item" or "2 x Item"
        if let regex = try? NSRegularExpression(pattern: #"^(\d+)\s*[xX×]\s+(.*)"#),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let qtyRange = Range(match.range(at: 1), in: trimmed),
           let nameRange = Range(match.range(at: 2), in: trimmed),
           let qty = Int(String(trimmed[qtyRange])), qty > 0, qty < 100 {
            return (String(trimmed[nameRange]).trimmingCharacters(in: .whitespaces), qty)
        }

        // "(2) Item"
        if let regex = try? NSRegularExpression(pattern: #"^\((\d+)\)\s+(.*)"#),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let qtyRange = Range(match.range(at: 1), in: trimmed),
           let nameRange = Range(match.range(at: 2), in: trimmed),
           let qty = Int(String(trimmed[qtyRange])), qty > 0, qty < 100 {
            return (String(trimmed[nameRange]).trimmingCharacters(in: .whitespaces), qty)
        }

        // "2 Item Name" (digit(s) at start, then text — quantity > 1 only)
        if let regex = try? NSRegularExpression(pattern: #"^(\d{1,2})\s+([A-Za-z].*)"#),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let qtyRange = Range(match.range(at: 1), in: trimmed),
           let nameRange = Range(match.range(at: 2), in: trimmed),
           let qty = Int(String(trimmed[qtyRange])), qty > 1, qty < 100 {
            return (String(trimmed[nameRange]).trimmingCharacters(in: .whitespaces), qty)
        }

        return (trimmed, 1)
    }

    // MARK: - Totals Extraction (Spatial)

    /// Extracts subtotal/tax/tip/discount/total from rows classified as the totals section.
    ///
    /// Uses a "pending category" strategy to handle the case where Vision splits a
    /// keyword and its price onto adjacent rows (e.g., "Gratuity" on one row,
    /// "$3.00" on the next). The last-seen keyword is held as pending and applied
    /// to the next price-only row if no keyword is found there.
    private func extractTotalsFromRows(_ rows: [TextRow]) -> (subtotal: Double?, tax: Double?, tip: Double?, discount: Double?, total: Double?) {
        var subtotal: Double?
        var tax: Double?
        var tip: Double?
        var discount: Double?
        var total: Double?
        var pendingCategory: String? = nil

        for row in rows {
            let lower = row.fullText.lowercased()
            let price = findPriceInRow(row)
            let category = totalsCategory(from: lower)

            if let cat = category {
                if let p = price {
                    // Keyword and price on the same row — straightforward
                    applyTotalsPrice(p, to: cat,
                                     subtotal: &subtotal, tax: &tax,
                                     tip: &tip, discount: &discount, total: &total)
                    pendingCategory = nil
                } else {
                    // Keyword row with no price — price is likely on the next row
                    pendingCategory = cat
                }
            } else if let p = price {
                if let pending = pendingCategory {
                    // Price-only row immediately following a keyword row
                    applyTotalsPrice(p, to: pending,
                                     subtotal: &subtotal, tax: &tax,
                                     tip: &tip, discount: &discount, total: &total)
                    pendingCategory = nil
                }
                // Price with no keyword and no pending context — skip (too ambiguous)
            }
        }

        return (subtotal, tax, tip, discount, total)
    }

    /// Maps a lowercased totals-section line to a category key.
    /// Returns nil if the line doesn't match any known totals keyword.
    private func totalsCategory(from lower: String) -> String? {
        if lower.contains("subtotal") || lower.contains("sub total") || lower.contains("sub-total") {
            return "subtotal"
        }
        if lower.contains("tax") || lower.contains("hst") || lower.contains("gst") || lower.contains("vat") {
            return "tax"
        }
        if lower.contains("tip") || lower.contains("gratuity") ||
           lower.contains("service charge") || lower.contains("service fee") ||
           lower.contains("auto grat") || lower.contains("grat") {
            return "tip"
        }
        if lower.contains("discount") || lower.contains("promo") ||
           lower.contains("coupon") || lower.contains("savings") {
            return "discount"
        }
        if lower.contains("total") || lower.contains("amount due") || lower.contains("balance") {
            return "total"
        }
        return nil
    }

    /// Applies a price value to the correct accumulator variable for a given category.
    private func applyTotalsPrice(
        _ price: Double, to category: String,
        subtotal: inout Double?, tax: inout Double?,
        tip: inout Double?, discount: inout Double?, total: inout Double?
    ) {
        switch category {
        case "subtotal": subtotal = price
        case "tax":      tax      = price
        case "tip":      tip      = price
        case "discount": discount = price
        case "total":    total    = price
        default: break
        }
        print("  💰 Totals: \(category) = $\(String(format: "%.2f", price))")
    }

    // MARK: - Restaurant Name Extraction

    /// Extracts the restaurant/business name from header rows (top of receipt).
    private func extractRestaurantNameFromHeader(_ rows: [TextRow]) -> String? {
        for row in rows.prefix(5) {
            let text = row.fullText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard text.count >= 3,
                  text.count <= 50,
                  !text.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" || $0 == "/" }),
                  !text.contains("www."),
                  !text.contains("http"),
                  !text.lowercased().contains("receipt"),
                  !text.lowercased().contains("invoice")
            else { continue }

            // If it contains mostly letters and common name characters, likely a name
            let letterCount = text.filter { $0.isLetter || $0 == " " || $0 == "'" || $0 == "&" || $0 == "-" }.count
            if Double(letterCount) / Double(text.count) > 0.6 {
                return text
            }
        }
        return nil
    }

    // MARK: - Section Detection

    /// Checks if a lowercased line indicates the start of the totals section.
    private func isTotalsKeyword(_ lower: String) -> Bool {
        let strict = [
            "subtotal", "sub total", "sub-total",
            "sales tax", "hst", "gst", "pst", "vat",
            "gratuity", "service charge",
            "amount due", "balance due",
            "change:", "payment:", "tender:"
        ]
        if strict.contains(where: { lower.hasPrefix($0) }) { return true }

        let ambiguous = ["total", "tax", "tip", "discount", "promo", "coupon", "cash", "credit", "debit"]
        for keyword in ambiguous {
            if lower.hasPrefix(keyword) {
                let after = lower.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces)
                if after.isEmpty || after.hasPrefix(":") || after.hasPrefix("$") || after.first?.isNumber == true {
                    return true
                }
            }
        }
        return false
    }

    /// Checks if a line is a visual separator (-----, =====, etc.)
    private func isSeparatorLine(_ text: String) -> Bool {
        let separatorChars: Set<Character> = ["-", "=", "_", ".", "*"]
        let separatorCount = text.filter { separatorChars.contains($0) }.count
        let nonWhitespace = text.filter { !$0.isWhitespace }.count
        return separatorCount > 3 && nonWhitespace > 0 && separatorCount == nonWhitespace
    }

    // MARK: - Confidence Calculation

    /// Calculates a 0.0–1.0 confidence score based on internal consistency checks.
    private func calculateConfidence(for receipt: ParsedReceipt) -> Double {
        var confidence = 0.0

        // Check 1: Has items
        if !receipt.items.isEmpty {
            confidence += 0.3
        }

        // Check 2: Has subtotal or total
        if receipt.subtotal != nil || receipt.total != nil {
            confidence += 0.2
        }

        // Check 3: Math validation (items total ≈ subtotal)
        if let subtotal = receipt.subtotal {
            let itemsTotal = receipt.items.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
            let difference = abs(itemsTotal - subtotal)
            let percentDiff = subtotal > 0 ? difference / subtotal : 1.0

            if percentDiff < 0.05 {
                confidence += 0.3
            } else if percentDiff < 0.15 {
                confidence += 0.15
            }
        }

        // Check 4: Has restaurant name
        if receipt.restaurantName != nil {
            confidence += 0.1
        }

        // Check 5: Total math (subtotal + tax + tip - discount ≈ total)
        if let total = receipt.total {
            let subtotalValue = receipt.subtotal ?? 0
            let taxValue = receipt.tax ?? 0
            let tipValue = receipt.tip ?? 0
            let discountValue = receipt.discount ?? 0

            let calculatedTotal = subtotalValue + taxValue + tipValue - discountValue
            let difference = abs(total - calculatedTotal)
            let percentDiff = total > 0 ? difference / total : 1.0

            if percentDiff < 0.05 {
                confidence += 0.1
            } else if percentDiff < 0.15 {
                confidence += 0.05
            }
        }

        return min(confidence, 1.0)
    }

    // MARK: - Cloud AI Parsing (Google Gemini - Free Tier)

    /// Sends the receipt image directly to Gemini (multimodal) for structured extraction.
    /// Sending the raw image bypasses OCR parsing entirely on the cloud side, letting
    /// Gemini's vision model read the receipt layout as a human would.
    private func parseReceiptWithGemini(image: UIImage, from lines: [String], apiKey: String) async -> ParsedReceipt {
        // Resize image so we stay well within Gemini's inline payload limits (~4 MB base64)
        let maxDimension: CGFloat = 1024
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }
        guard let jpegData = resized.jpegData(compressionQuality: 0.75), !jpegData.isEmpty else {
            print("❌ Gemini: could not encode image")
            return ParsedReceipt(restaurantName: nil, items: [], subtotal: nil, tax: nil, tip: nil, discount: nil, total: nil)
        }
        let base64Image = jpegData.base64EncodedString()

        // OCR text is included as extra context for robustness
        let ocrContext = lines.isEmpty ? "" : "\n\nFor reference, OCR extracted these text lines:\n" + lines.joined(separator: "\n")

        let prompt = """
        You are looking at a photo of a restaurant/store receipt. Extract the information and return ONLY valid JSON, no markdown:

        {
          "restaurant": "name or empty string",
          "items": [{"name": "string", "quantity": number, "price": number (unit price per item)}],
          "subtotal": number or null,
          "tax": number or null,
          "tip": number or null,
          "discount": number or null,
          "total": number or null
        }

        Rules:
        - Items are food/drinks ONLY
        - NEVER include "Tax", "Tip", "Subtotal", "Total" as items
        - Price is the UNIT price per single item (divide line total by quantity if needed)
        - Clean up item names, removing quantity prefixes and special characters
        - For multi-line items (name on one line, price below), combine into one item\(ocrContext)
        """

        do {
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent?key=\(apiKey)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let requestBody: [String: Any] = [
                "contents": [
                    [
                        "parts": [
                            // Image comes first so the model's vision grounding is anchored
                            [
                                "inline_data": [
                                    "mime_type": "image/jpeg",
                                    "data": base64Image
                                ]
                            ],
                            ["text": prompt]
                        ]
                    ]
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ Gemini API error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return ParsedReceipt(restaurantName: nil, items: [], subtotal: nil, tax: nil, tip: nil, discount: nil, total: nil)
            }

            // Parse Gemini response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let content = firstCandidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String {

                // Extract JSON from response (might be wrapped in markdown)
                let cleanedText = text
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let receiptData = try JSONSerialization.jsonObject(with: cleanedText.data(using: .utf8)!) as! [String: Any]

                var receipt = ParsedReceipt(
                    restaurantName: receiptData["restaurant"] as? String,
                    items: [],
                    subtotal: receiptData["subtotal"] as? Double,
                    tax: receiptData["tax"] as? Double,
                    tip: receiptData["tip"] as? Double,
                    discount: receiptData["discount"] as? Double,
                    total: receiptData["total"] as? Double
                )

                // Parse items
                if let itemsArray = receiptData["items"] as? [[String: Any]] {
                    receipt.items = itemsArray.compactMap { itemDict in
                        guard let name = itemDict["name"] as? String,
                              let price = itemDict["price"] as? Double else { return nil }
                        let quantity = itemDict["quantity"] as? Int ?? 1
                        return ParsedLineItem(name: name, price: price, quantity: quantity)
                    }
                }

                receipt.parsingMethod = .cloudAI
                receipt.confidence = calculateConfidence(for: receipt)

                print("✨ Gemini extracted: \(receipt.items.count) items")
                return receipt
            }

        } catch {
            print("❌ Gemini parsing failed: \(error)")
        }

        return ParsedReceipt(restaurantName: nil, items: [], subtotal: nil, tax: nil, tip: nil, discount: nil, total: nil)
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
        @Guide(description: "The name of the food or drink item, cleaned up and without quantity prefixes like '2x' or '4'. Remove any asterisks, special characters, or item codes.")
        var name: String

        @Guide(description: "The quantity/count of this item. Look for patterns like '4x Item', '4 Item', '(4) Item', or 'Item x4'. If quantity is shown separately from the price, extract it carefully. Default to 1 if not specified.", .range(1...99))
        var quantity: Int

        @Guide(description: "The UNIT price for ONE item in dollars. If the receipt shows '4 Fried Rice $100.00', the price should be $25.00 (100 / 4). Extract carefully to avoid confusion between unit price and total price.", .range(0.01...1000.0))
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
        You are an expert receipt parser that understands receipt structure. Extract information with high accuracy.

        RECEIPT STRUCTURE - Understanding the layout:
        Receipts follow this standard format:

        1. HEADER (top of receipt):
           - Restaurant/business name
           - Address, phone, date, time
           - Order/table number

        2. ITEMS SECTION (middle):
           - This is what you need to extract as "items"
           - Food and drink items with prices
           - This section ENDS when you see keywords like "Subtotal", "Tax", "Total"

        3. TOTALS SECTION (bottom):
           - Subtotal, Tax, Tip, Discount, Total
           - These are NOT items - extract them separately
           - This section STARTS with keywords like "Subtotal" or "Tax"

        4. FOOTER (very bottom):
           - Thank you message, payment method
           - Transaction details

        What to extract:
        - Restaurant name: From the HEADER section only. If unclear, return empty string.
        - Items: ONLY from the ITEMS SECTION (before subtotal/tax/total lines)
        - Subtotal, Tax, Tip, Discount, Total: From the TOTALS SECTION

        What to ignore:
        - Addresses, phone numbers, website URLs
        - Payment method details (card numbers, transaction IDs)
        - Date and time stamps
        - Server/cashier names, order numbers
        - DO NOT extract "Tax", "Tip", "Subtotal", "Total" as items!

        EXAMPLE RECEIPT STRUCTURE:

        ```
        Joe's Diner                    ← HEADER (extract restaurant name)
        123 Main St
        Order #123
        -------------------------------
        Burger              $12.00     ← ITEMS SECTION
        2x Fries            $8.00      ← (extract these as items)
        Coke                $3.00
        -------------------------------
        Subtotal            $23.00     ← TOTALS SECTION
        Tax                 $1.84      ← (extract these as subtotal/tax/etc)
        Tip                 $4.00      ← NOT items!
        -------------------------------
        Total               $28.84
        ```

        For this receipt, you should extract:
        - restaurantName: "Joe's Diner"
        - items: [
            {name: "Burger", quantity: 1, price: 12.00},
            {name: "Fries", quantity: 2, price: 4.00},  ← unit price!
            {name: "Coke", quantity: 1, price: 3.00}
          ]
        - subtotal: 23.00
        - tax: 1.84
        - tip: 4.00
        - total: 28.84

        CRITICAL: "Tax", "Tip", "Subtotal", "Total" are NEVER items to buy!

        CRITICAL RULES for items with quantities:

        1. UNIT PRICE vs TOTAL PRICE - THE MOST IMPORTANT RULE:
           - The 'price' field must ALWAYS be the unit price per single item
           - If receipt shows "4 Fried Rice    $100.00", this means:
             * Total for all 4 items: $100.00
             * You must return: quantity=4, price=25.00
             * Calculate: price = $100.00 ÷ 4 = $25.00 per item

        2. Common receipt formats to handle:
           Format A: "4 Fried Rice         $100.00"
             → quantity: 4, price: 25.00 (100/4)

           Format B: "2x Burger @ $15.00    $30.00"
             → quantity: 2, price: 15.00 (unit price shown explicitly)

           Format C: "Salad                 $12.50"
             → quantity: 1, price: 12.50

           Format D: "(3) Pizza             $45.00"
             → quantity: 3, price: 15.00 (45/3)

        3. Quantity detection patterns:
           - "4x Item", "4 Item", "(4) Item", "Item x4" all mean quantity 4
           - If quantity shown separately from price, extract it
           - If no quantity shown, default to 1

        4. Price location on receipts:
           - The rightmost number is usually the TOTAL for that line
           - If quantity > 1, you MUST divide that total by quantity
           - Example: "5 Wings   $50.00" → the $50 is total, so price = $50 ÷ 5 = $10 per wing

        5. Validation - CHECK YOUR WORK:
           - Calculate: sum of (quantity × price) for all items
           - This sum should equal or be very close to the subtotal
           - If they don't match, you've made an error in calculating unit prices
           - Go back and recalculate, ensuring you divided totals by quantities

        6. Clean item names:
           - Remove quantity prefixes from names
           - Remove asterisks, item codes, special characters
           - Keep only the food/drink name

        EXAMPLES OF CORRECT EXTRACTION:

        Receipt: "4 Fried Rice           $100.00"
        ✅ CORRECT: name="Fried Rice", quantity=4, price=25.00
        ❌ WRONG: name="Fried Rice", quantity=4, price=100.00

        Receipt: "10 Wings               $150.00"
        ✅ CORRECT: name="Wings", quantity=10, price=15.00
        ❌ WRONG: name="Wings", quantity=10, price=150.00

        Receipt: "1 Salad                $12.50"
        ✅ CORRECT: name="Salad", quantity=1, price=12.50

        Remember: The price field is ALWAYS the price for ONE item, not the line total!
        """

        let session = LanguageModelSession(instructions: instructions)

        do {
            let response = try await session.respond(
                to: "Extract all information from this receipt. Pay special attention to quantities and calculate unit prices correctly:\n\n\(fullText)",
                generating: ReceiptData.self
            )

            let data = response.content

            // Validate the extracted data with detailed logging
            let itemsTotal = data.items.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
            let expectedSubtotal = data.subtotal ?? itemsTotal
            let difference = abs(itemsTotal - expectedSubtotal)

            print("🔍 AI Extraction Validation:")
            print("  Items total (qty × price): $\(String(format: "%.2f", itemsTotal))")
            print("  Subtotal from receipt: $\(String(format: "%.2f", expectedSubtotal))")
            print("  Difference: $\(String(format: "%.2f", difference))")

            // Log each item for debugging
            for item in data.items {
                let lineTotal = item.price * Double(item.quantity)
                print("  📦 \(item.quantity)x \(item.name) @ $\(String(format: "%.2f", item.price)) = $\(String(format: "%.2f", lineTotal))")
            }

            if difference > (expectedSubtotal * 0.05) { // More than 5% difference
                print("⚠️ AI extraction validation warning: items total (\(itemsTotal)) differs from subtotal (\(expectedSubtotal)) by \(difference)")
                print("⚠️ This suggests the AI may have extracted total prices instead of unit prices.")

                // Attempt automatic correction: if the items total is exactly N times the expected subtotal,
                // the AI probably didn't divide by quantity
                let ratio = itemsTotal / expectedSubtotal
                if ratio > 1.5 && ratio < 10.0 { // Reasonable multiplier range
                    print("🔧 Attempting automatic correction...")
                    let correctedItems = data.items.map { item -> ReceiptLineItem in
                        if item.quantity > 1 {
                            // Recalculate: assume the AI gave us total price, divide by quantity
                            print("  Correcting: \(item.quantity)x \(item.name) from $\(item.price) to $\(item.price / Double(item.quantity))")
                            return ReceiptLineItem(name: item.name, quantity: item.quantity, price: item.price / Double(item.quantity))
                        }
                        return item
                    }

                    // Verify correction worked
                    let correctedTotal = correctedItems.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
                    let correctedDiff = abs(correctedTotal - expectedSubtotal)

                    if correctedDiff < difference { // Correction improved things
                        print("✅ Correction successful! New total: $\(String(format: "%.2f", correctedTotal))")

                        // Only use restaurant name if it's meaningful
                        let restaurantName = data.restaurantName.trimmingCharacters(in: .whitespacesAndNewlines)

                        return ParsedReceipt(
                            restaurantName: restaurantName.isEmpty ? nil : restaurantName,
                            items: correctedItems.map { ParsedLineItem(name: $0.name, price: $0.price, quantity: $0.quantity) },
                            subtotal: data.subtotal,
                            tax: data.tax,
                            tip: data.tip,
                            discount: data.discount,
                            total: data.total
                        )
                    }
                }
            } else {
                print("✅ Validation passed: totals match within acceptable margin")
            }

            // Only use restaurant name if it's meaningful
            let restaurantName = data.restaurantName.trimmingCharacters(in: .whitespacesAndNewlines)

            return ParsedReceipt(
                restaurantName: restaurantName.isEmpty ? nil : restaurantName,
                items: data.items.map { ParsedLineItem(name: $0.name, price: $0.price, quantity: $0.quantity) },
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

    // MARK: - Filters & Cleanup

    /// Returns true for lines that are definitely not item lines.
    private func isNoise(_ line: String) -> Bool {
        let lower = line.lowercased()

        // Very short lines are noise
        if line.count < 3 { return true }

        // Lines that are purely numeric (page numbers, order numbers, etc.)
        if line.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "/" }) { return true }

        // Separator lines (dashes, equals, underscores)
        if isSeparatorLine(line) { return true }

        // Common receipt boilerplate
        let boilerplatePatterns = [
            "thank you", "have a nice", "come again", "visit us",
            "www.", "http", "tel:", "phone:", "fax:", "email:",
            "order #", "order#", "table #", "receipt #",
            "server:", "cashier:", "served by:",
            "transaction", "approval", "auth #",
            "date:", "time:", "open:", "close:", "hours:",
        ]

        for pattern in boilerplatePatterns {
            if lower.hasPrefix(pattern) || lower == pattern {
                return true
            }
        }

        // Common footer phrases
        if lower.contains("thank you for") ||
           lower.contains("please come again") ||
           lower.contains("visit us at") {
            return true
        }

        // Card types ONLY if they appear alone (not "Cash Chicken" as an item)
        let cardTypes = ["visa", "mastercard", "amex", "discover"]
        if cardTypes.contains(lower) {
            return true
        }

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
