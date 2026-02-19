//
//  Person.swift
//  CheckMate
//
//  Created by Syam Shukla on 2/18/26.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Person {
    var name: String
    var emoji: String
    var color: String

    init(
        name: String,
        emoji: String = "👤",
        color: String = Person.colorPalette[0]
    ) {
        self.name = name
        self.emoji = emoji
        self.color = color
    }

    var swiftUIColor: Color {
        Color(hex: color)
    }

    var displayName: String {
        "\(emoji) \(name)"
    }

    // Vibrant color palette for people chips
    static let colorPalette: [String] = [
        "FF6B6B", // coral
        "4ECDC4", // teal
        "45B7D1", // sky
        "FFA07A", // salmon
        "C3A6FF", // lavender
        "F7DC6F", // gold
        "82E0AA", // mint
        "F1948A", // rose
    ]

    static func nextColor(avoiding existing: [Person]) -> String {
        let usedColors = Set(existing.map { $0.color })
        return colorPalette.first { !usedColors.contains($0) }
            ?? colorPalette[existing.count % colorPalette.count]
    }
}

// MARK: - Color helpers (shared across app)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let rgb = Int(hex, radix: 16) ?? 0xFF6B6B

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    // MARK: App design tokens
    static let appBackground  = Color(hex: "1C1C1E")
    static let cardBackground = Color(hex: "2C2C2E")
    static let elevatedCard   = Color(hex: "3A3A3C")
    static let appAccent      = Color(hex: "6C63FF")
    static let textSecondary  = Color(hex: "8E8E93")
    static let appDestructive = Color(hex: "FF453A")
    static let appWarning     = Color(hex: "FF9F0A")
}

// MARK: - ShapeStyle shorthands
// Mirrors how SwiftUI exposes .blue / .red etc. so our tokens work with
// .foregroundStyle(.appAccent) without needing an explicit Color. prefix.
extension ShapeStyle where Self == Color {
    static var appBackground:  Color { .init(hex: "1C1C1E") }
    static var cardBackground: Color { .init(hex: "2C2C2E") }
    static var elevatedCard:   Color { .init(hex: "3A3A3C") }
    static var appAccent:      Color { .init(hex: "6C63FF") }
    static var textSecondary:  Color { .init(hex: "8E8E93") }
    static var appDestructive: Color { .init(hex: "FF453A") }
    static var appWarning:     Color { .init(hex: "FF9F0A") }
}
