//
//  OCRService.swift
//  CheckMate
//
//  Created by Syam Shukla on 2/18/26.
//

import UIKit
import Vision
import Foundation

struct ParsedLineItem {
    var name: String
    var price: Double
}

class OCRService {
    static let shared = OCRService()
    private init() {}

    // MARK: - Public

    func extractLineItems(from image: UIImage) async -> [ParsedLineItem] {
        guard let cgImage = image.cgImage else { return [] }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        var rawLines: [String] = []

        let request = VNRecognizeTextRequest { req, _ in
            guard let results = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in results {
                if let top = obs.topCandidates(1).first {
                    rawLines.append(top.string)
                }
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true

        do {
            try handler.perform([request])
        } catch {
            print("OCR Error: \(error)")
            return []
        }

        let items = parseLineItems(from: rawLines)
        print("OCR extracted \(rawLines.count) lines → \(items.count) items")
        return items
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
