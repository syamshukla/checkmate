// PROJECT_ARCHITECTURE.md
// CheckMate - Complete Project Architecture

# CheckMate Project Architecture

Complete scaffolding for a bill-splitting iOS app using SwiftUI, SwiftData, and Vision framework.

## 📁 Project Structure

```
CheckMate/
├── CheckMate/
│   ├── CheckMateApp.swift              # App entry point with SwiftData setup
│   ├── ContentView.swift               # Main content router
│   ├── Item.swift                      # Legacy model (kept for compatibility)
│   │
│   ├── Models/                         # SwiftData models
│   │   ├── Receipt.swift               # Receipt model with relationships
│   │   ├── LineItem.swift              # Line item model with person assignment
│   │   ├── Person.swift                # Person model with emoji/color
│   │   └── Split.swift                 # Split calculation results model
│   │
│   ├── Services/                       # Business logic services
│   │   ├── OCRService.swift            # Vision framework OCR extraction
│   │   └── SplitCalculatorService.swift # Tax/tip weighted distribution
│   │
│   ├── Views/                          # SwiftUI views
│   │   ├── HomeView.swift              # Receipt list & entry point
│   │   ├── ScanView.swift              # Camera capture & item parsing
│   │   ├── ReviewReceiptView.swift     # Edit receipt before assignment
│   │   ├── AssignItemsView.swift       # Assign items to people
│   │   └── SplitSummaryView.swift      # Show what each person owes
│   │
│   └── Assets.xcassets/
│
├── CheckMateTests/
├── CheckMateUITests/
└── CheckMate.xcodeproj/
```

## 🏗️ Data Models

### Receipt
```swift
@Model
final class Receipt {
    var date: Date                           // When scanned
    var restaurantName: String               // Restaurant name
    var subtotal: Double                     // Sum of line items
    var tax: Double                          // Tax amount
    var tip: Double                          // Tip amount
    var total: Double                        // Total = subtotal + tax + tip
    
    @Relationship(deleteRule: .cascade) 
    var lineItems: [LineItem] = []           // Items on receipt
    
    @Relationship(deleteRule: .cascade) 
    var splits: [Split] = []                 // How split among people
}
```

### LineItem
```swift
@Model
final class LineItem {
    var name: String                         // Item name
    var price: Double                        // Unit price
    var quantity: Int                        // How many
    
    var receipt: Receipt?                    // Parent receipt
    var assignedPerson: Person?              // Who ordered it
    
    var totalPrice: Double { price * Double(quantity) }
}
```

### Person
```swift
@Model
final class Person {
    var name: String                         // Person's name
    var emoji: String                        // Visual identifier
    var color: String                        // Hex color for UI
    
    var swiftUIColor: Color                  // Computed color
    var displayName: String                  // "emoji name"
}
```

### Split
```swift
@Model
final class Split {
    var receipt: Receipt?                    // Reference to receipt
    var person: Person?                      // Which person
    var amountOwed: Double                   // Total they owe
    var itemsSubtotal: Double                // Their portion of items
    var taxAmount: Double                    // Their portion of tax
    var tipAmount: Double                    // Their portion of tip
    
    var breakdown: (subtotal: Double, tax: Double, tip: Double)
}
```

## 🔧 Services

### OCRService
**Location:** `Services/OCRService.swift`

Extracts text using Apple Vision framework and parses line items.

**Key Components:**
- `ParsedLineItem` struct: Contains extracted `name` and `price`
- `extractLineItems(from: UIImage) -> [ParsedLineItem]` - Main async method
- Uses `VNRecognizeTextRequest` for text recognition
- Regex patterns to extract prices (handles $, €, £, ¥, ₹, ₽, ₩)
- Filters duplicate items and noise
- Skips receipt headers/footers

**Usage:**
```swift
let items = await OCRService.shared.extractLineItems(from: image)
// Returns: [ParsedLineItem(name: "Burger", price: 15.99), ...]
```

### SplitCalculatorService
**Location:** `Services/SplitCalculatorService.swift`

Calculates weighted distribution of tax and tip among people.

**Key Components:**
- `SplitDetails` struct: Contains `subtotal`, `tax`, `tip`, `total` + formatted versions
- `SplitSummary` struct: Contains metadata about split (people count, item counts, etc.)
- `calculateSplit()` - Weighted by item subtotal
- `calculateEqualSplit()` - Equal split among all people
- `validateAllItemsAssigned()` - Check completion
- `getSummary()` - Get statistics

**Usage:**
```swift
let splits = SplitCalculatorService.shared.calculateSplit(
    lineItems: receipt.lineItems,
    taxAmount: receipt.tax,
    tipAmount: receipt.tip
)
// Returns: [Person: SplitDetails] - what each person owes
```

## 🎨 Views

### HomeView
**Purpose:** Lists past receipts and entry point to scan new ones

**Features:**
- Query receipts sorted by date (newest first)
- Shows restaurant name + date + total
- Delete receipt swipe action
- New receipt button → opens ScanView
- Empty state guidance

**Navigation:** → ScanView or ReviewReceiptView

### ScanView
**Purpose:** Capture receipt photo and initial parsing

**Features:**
- Camera permission request with validation
- Camera or photo library selection
- Image preview
- Call OCRService to extract items
- Restaurant name input via RestaurantInputView
- Creates Receipt draft with parsed LineItems
- Navigation to ReviewReceiptView

**Subcomponents:**
- `ImagePicker` - UIImagePickerControllerRepresentable wrapper
- `RestaurantInputView` - Form for restaurant name input

**Navigation:** → ReviewReceiptView

### ReviewReceiptView
**Purpose:** Edit parsed items and adjust tax/tip before splitting

**Features:**
- Edit receipt details (name, date)
- Add/edit/delete line items
- Adjust tax and tip amounts
- Manual item editing via sheet
- Shows running totals
- Calculates total = subtotal + tax + tip
- Navigation to AssignItemsView

**Subcomponents:**
- `AddLineItemSheet` - Form to add/edit items

**Navigation:** → AssignItemsView

### AssignItemsView
**Purpose:** Assign line items to people and calculate splits

**Features:**
- Add people with emoji + color
- View people and their assigned items
- Assign unassigned items via menu
- Shows item count per person
- Validates all items assigned
- Calculates splits automatically
- Navigation to detailed assignment

**Subcomponents:**
- `PersonAssignmentView` - Shows items for one person
- `AddPersonSheet` - Form to add new person

**Navigation:** → PersonAssignmentView or SplitSummaryView

### SplitSummaryView
**Purpose:** Show final breakdown of what everyone owes

**Features:**
- Displays receipt header (name, date, total)
- Card for each person showing:
  - Emoji + name + total owed
  - Itemization (subtotal / tax / tip breakdown)
- Save splits to SwiftData
- Returns to HomeView on save

**Subcomponents:**
- `SplitDetailCard` - Card for each person
- `SplitBreakdownRow` - Shows line item amounts

**Navigation:** → HomeView (save) or back (edit)

## 🔄 Data Flow

```
HomeView (receipts list)
    ↓
[+ Scan] → ScanView (camera)
    ↓
OCRService extracts items
    ↓
RestaurantInputView (name)
    ↓
ReviewReceiptView (edit items, tax, tip)
    ↓
AssignItemsView (assign to people)
    ↓
AssignItemsView lists people
    ↓
[Next] → SplitSummaryView (shows breakdown)
    ↓
SplitCalculatorService calculates splits
    ↓
[Save] → Create Split records
    ↓
Back to HomeView (receipt saved)
```

## 🔐 SwiftData Integration

All models use `@Model` macro for automatic persistence.

**In CheckMateApp.swift:**
```swift
let schema = Schema([
    Item.self,
    Receipt.self,
    LineItem.self,
    Person.self,
    Split.self,
])
```

**Models auto-sync to device storage:**
- No manual SQL
- Relationships managed automatically
- Queries with @Query macro
- Insert/delete with modelContext

**Example Query:**
```swift
@Query(sort: \Receipt.date, order: .reverse) var receipts: [Receipt]
```

## 📱 Key Features

✅ **Camera Integration**
- Uses UIImagePickerController with camera source type
- Photo library fallback
- Handles camera permission gracefully

✅ **OCR Parsing**
- Vision framework text recognition
- Price extraction with regex
- Filters duplicates and noise
- Handles multiple currencies

✅ **Bill Splitting**
- Weighted by item amount
- Equal distribution option
- Automatic tax/tip allocation
- Per-person breakdown

✅ **Data Persistence**
- SwiftData automatic sync
- Receipt history
- Person library (reusable)
- Split tracking

✅ **User Experience**
- Tab-based navigation
- Modal flows
- Form validation
- Progress indicators
- Empty states

## 🔗 Dependencies

All built into iOS 17+:
- **SwiftUI** - UI framework
- **SwiftData** - Data persistence
- **Vision** - OCR text recognition
- **AVFoundation** - Camera access

No external packages required!

## ⚙️ Configuration

**Info.plist Required:**
```xml
<key>NSCameraUsageDescription</key>
<string>CheckMate needs camera access to scan receipts</string>
```

**Build Settings:**
- iOS 17+ target
- SwiftUI views support
- SwiftData enabled
- Vision framework included

## 🧪 Testing

**Model Tests:**
```swift
let receipt = Receipt(restaurantName: "Test", subtotal: 50, tax: 5, tip: 10)
let item = LineItem(name: "Burger", price: 15)
receipt.lineItems.append(item)
```

**Service Tests:**
```swift
let splits = SplitCalculatorService.shared.calculateSplit(
    lineItems: items,
    taxAmount: 5,
    tipAmount: 10
)
XCTAssertEqual(splits.count, 2)
```

**View Tests:**
- Use preview providers
- Test with in-memory ModelContainer
- Validate navigation flows

## 🚀 Next Steps

Optional enhancements:
1. Image storage in SwiftData
2. Receipt photo display
3. Receipt search/filtering
4. Export to CSV/email
5. Receipt templates
6. History analytics
7. Multi-currency support
8. Expense categories
9. Social sharing
10. Cloud sync

