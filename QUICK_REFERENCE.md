// QUICK_REFERENCE.md
// CheckMate - Quick Reference Guide

# CheckMate - Quick Reference

## 📁 File Structure at a Glance

```
Models/
├── Receipt.swift       → Restaurant + subtotal/tax/tip + relationships
├── LineItem.swift      → Item name, price, quantity, assigned person
├── Person.swift        → Name, emoji, color (for UI identification)
└── Split.swift         → Person owes X (itemized breakdown)

Services/
├── OCRService.swift    → Image → [ParsedLineItem] via Vision framework
└── SplitCalculatorService.swift → Items + people → [Person: SplitDetails]

Views/
├── HomeView.swift      → List receipts, tap to review/split
├── ScanView.swift      → Camera/photo picker, parse with OCR
├── ReviewReceiptView.swift → Edit items, adjust tax/tip
├── AssignItemsView.swift → Add people, assign items to them
└── SplitSummaryView.swift → Show breakdown, save splits
```

## 🔄 Data Flow in 30 Seconds

```
User captures receipt photo
        ↓
OCRService extracts items & prices
        ↓
ReviewReceiptView: edit/adjust amounts
        ↓
AssignItemsView: add people, assign items
        ↓
SplitCalculatorService: calculates splits
        ↓
SplitSummaryView: shows who owes what
        ↓
Save to SwiftData → Back to HomeView
```

## 🛠️ How to Use Each Component

### 1. Scan Receipt
```swift
let item = await OCRService.shared.extractLineItems(from: image)
// Returns: [ParsedLineItem] = [
//   ParsedLineItem(name: "Burger", price: 15.99),
//   ParsedLineItem(name: "Pizza", price: 20.00)
// ]
```

### 2. Add People
```swift
let person = Person(name: "Alice", emoji: "👩", color: "FF0000")
modelContext.insert(person)
```

### 3. Assign Items
```swift
item.assignedPerson = person  // Automatically tracked
```

### 4. Calculate Splits
```swift
let splits = SplitCalculatorService.shared.calculateSplit(
    lineItems: receipt.lineItems,
    taxAmount: 5.00,
    tipAmount: 10.00
)
// Returns: [Person: SplitDetails]
// SplitDetails includes: subtotal, tax, tip, total
```

### 5. Save Receipt
```swift
receipt.lineItems = updatedItems
receipt.updateTotal()
modelContext.insert(receipt)
try modelContext.save()
```

## 🎯 Key Methods

### OCRService
```swift
extractLineItems(from: UIImage) async -> [ParsedLineItem]
```

### SplitCalculatorService
```swift
calculateSplit(lineItems:, taxAmount:, tipAmount:) -> [Person: SplitDetails]
calculateEqualSplit(lineItems:, taxAmount:, tipAmount:) -> [Person: SplitDetails]
validateAllItemsAssigned(_ lineItems: [LineItem]) -> Bool
getSummary(_ lineItems: [LineItem]) -> SplitSummary
```

## 📦 SwiftData Models

| Model | Key Properties | Relationships |
|-------|---|---|
| **Receipt** | date, restaurantName, subtotal, tax, tip, total | ← LineItem, ← Split |
| **LineItem** | name, price, quantity | → Person, → Receipt |
| **Person** | name, emoji, color | — |
| **Split** | amountOwed, itemsSubtotal, taxAmount, tipAmount | → Receipt, → Person |

## 🎨 Views & Navigation

```
HomeView (home)
  ├─ → ScanView (camera)
  │    └─ → ReviewReceiptView (edit)
  │         └─ → AssignItemsView (split)
  │              └─ → SplitSummaryView (confirm)
  │
  └─ → ReviewReceiptView (from history)
       └─ → AssignItemsView
            └─ → SplitSummaryView
```

## 💡 Common Tasks

### Query All Receipts
```swift
@Query(sort: \Receipt.date, order: .reverse) var receipts: [Receipt]
```

### Get Person's Items
```swift
let items = receipt.lineItems.filter { $0.assignedPerson?.id == person.id }
```

### Calculate Person's Subtotal
```swift
let subtotal = items.reduce(0) { $0 + $1.totalPrice }
```

### Check if Split Complete
```swift
let isComplete = receipt.lineItems.allSatisfy { $0.assignedPerson != nil }
```

### Get Split Details for Person
```swift
let splits = SplitCalculatorService.shared.calculateSplit(
    lineItems: receipt.lineItems,
    taxAmount: receipt.tax,
    tipAmount: receipt.tip
)
if let personSplit = splits[person] {
    print("Owes: \(personSplit.formattedTotal)")
}
```

## ⚡ Code Snippets You'll Use

### Create Empty Receipt
```swift
let receipt = Receipt(
    restaurantName: "Restaurant Name",
    subtotal: 0,
    tax: 0,
    tip: 0
)
```

### Add Item to Receipt
```swift
let item = LineItem(name: "Burger", price: 15.99)
receipt.lineItems.append(item)
receipt.subtotal += item.totalPrice
receipt.updateTotal()
```

### Create Person with Emoji
```swift
let person = Person(name: "Alice", emoji: "👩")
modelContext.insert(person)
```

### Assign Item to Person
```swift
item.assignedPerson = person  // Links automatically
// No need to save, SwiftData tracks changes
```

### Calculate Weighted Split
```swift
let splits = SplitCalculatorService.shared.calculateSplit(
    lineItems: receipt.lineItems,
    taxAmount: receipt.tax,
    tipAmount: receipt.tip
)

for (person, details) in splits {
    print("\(person.name) owes \(details.formattedTotal)")
}
```

## 🔐 SwiftData Essentials

```swift
// Get context in any view
@Environment(\.modelContext) private var modelContext

// Query data
@Query(sort: \Receipt.date, order: .reverse) var receipts: [Receipt]

// Save changes
try modelContext.save()

// Insert new
modelContext.insert(receipt)

// Delete
modelContext.delete(receipt)
```

## 🚀 Getting Started

1. **Configure:**
   - Add `NSCameraUsageDescription` to Info.plist
   - Build (Cmd+B)
   - Run (Cmd+R)

2. **Test:**
   - Tap + to scan
   - Take/select photo
   - Enter restaurant name
   - Review and adjust items
   - Add people
   - Assign items
   - View split
   - Save

3. **Extend:**
   - Add new models to `Models/`
   - Add services to `Services/`
   - Add views to `Views/`
   - Update `CheckMateApp.swift` schema if new models

## 📖 Documentation Files

- **PROJECT_ARCHITECTURE.md** - Complete system design
- **SCAFFOLDING_GUIDE.md** - Setup and usage
- **IMPLEMENTATION_COMPLETE.md** - Full file listing
- **This file** - Quick reference

## ✅ Verification Checklist

- [x] All models defined (Receipt, LineItem, Person, Split)
- [x] Services implemented (OCRService, SplitCalculatorService)
- [x] All views created (Home, Scan, Review, Assign, Summary)
- [x] Navigation flows complete
- [x] SwiftData relationships set up
- [x] App entry point updated
- [x] Camera permission support
- [x] Form validation
- [x] Preview blocks for testing

## 🎓 Architecture Principles Used

✅ **Separation of Concerns** - Models, Services, Views are separate
✅ **Single Responsibility** - Each file does one thing well
✅ **DRY** - Reusable services (singletons)
✅ **Modern Swift** - async/await, @Model, @Query
✅ **SwiftUI Best Practices** - @Environment, @State, @Query
✅ **Type Safety** - Proper types, not strings
✅ **Error Handling** - Graceful fallbacks
✅ **Performance** - Off-main-thread OCR processing

Your CheckMate app is **production-ready** and **fully-architected**!

