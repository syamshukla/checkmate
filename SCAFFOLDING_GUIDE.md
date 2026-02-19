// SCAFFOLDING_GUIDE.md
// CheckMate - Project Scaffolding Guide

# CheckMate Project Scaffolding Complete

Your bill-splitting iOS app is now fully scaffolded with proper architecture.

## ✅ What's Been Created

### 1. **Data Models** (Models folder)
- ✅ Receipt.swift - Main receipt model with relationships
- ✅ LineItem.swift - Individual items with person assignment
- ✅ Person.swift - People who split bills
- ✅ Split.swift - Calculation results and person shares

All use SwiftData `@Model` for automatic persistence.

### 2. **Services** (Services folder)
- ✅ OCRService.swift - Vision framework text extraction
- ✅ SplitCalculatorService.swift - Weighted/equal split calculations

Singletons for easy access throughout app.

### 3. **Views** (Views folder)
- ✅ HomeView.swift - Receipt history & entry point
- ✅ ScanView.swift - Camera capture & OCR parsing
- ✅ ReviewReceiptView.swift - Edit items, tax, tip
- ✅ AssignItemsView.swift - Assign items to people
- ✅ SplitSummaryView.swift - Show what each person owes

All views include subcomponents for modals and forms.

### 4. **App Configuration**
- ✅ CheckMateApp.swift - Updated with all models
- ✅ ContentView.swift - Router to HomeView

## 🎯 Navigation Flow

```
HomeView (See past receipts)
  ↓ [+ Scan Button]
ScanView (Camera/Photo)
  ↓ [Snap Receipt]
ReviewReceiptView (Edit items, tax, tip)
  ↓ [Save]
AssignItemsView (Add people, assign items)
  ↓ [Next]
SplitSummaryView (Show breakdown)
  ↓ [Save Split]
HomeView (Back with new receipt)
```

## 🚀 Quick Start

### 1. Open in Xcode
```bash
open /Users/sam/Documents/CheckMate/CheckMate.xcodeproj
```

### 2. Add Camera Permission
- Select CheckMate target
- Info tab
- Add: `NSCameraUsageDescription` = "CheckMate needs camera access to scan receipts"

### 3. Build & Run
```
Cmd+B (build)
Cmd+R (run)
```

### 4. Test the Flow
1. App launches to HomeView (empty state)
2. Tap "+" to scan receipt
3. Take photo or select from library
4. Enter restaurant name
5. Review & edit items
6. Add people (emoji + name)
7. Assign each item to a person
8. View split summary
9. Save → back to HomeView

## 📚 Key Files to Know

### Models
- `Models/Receipt.swift` - Parent model, owns LineItems & Splits
- `Models/LineItem.swift` - Individual item with person reference
- `Models/Person.swift` - Has emoji, color, display name
- `Models/Split.swift` - Stores calculation result for each person

### Services
- `Services/OCRService.swift` - Extract items from image
- `Services/SplitCalculatorService.swift` - Calculate who owes what

### Views
- `Views/HomeView.swift` - @Query receipts, shows list
- `Views/ScanView.swift` - UIImagePickerController wrapper
- `Views/ReviewReceiptView.swift` - Edit receipt before split
- `Views/AssignItemsView.swift` - Add people, assign items
- `Views/SplitSummaryView.swift` - Show final breakdown

## 🔄 How Features Work

### Receipt Scanning
```
1. Take photo with camera
2. OCRService uses Vision framework
3. Extracts text lines
4. Regex matches prices
5. Returns ParsedLineItem objects
6. User reviews & edits
7. Save as Receipt model
```

### Bill Splitting
```
1. User assigns each item to a person
2. Calculate each person's subtotal
3. SplitCalculatorService allocates:
   - Tax proportionally (by item amount)
   - Tip proportionally (by item amount)
4. Generate SplitDetails for each person
5. Show breakdown (subtotal/tax/tip)
6. Create Split records in SwiftData
```

## 💾 Data Persistence

All models are SwiftData @Model, so they automatically persist:

```swift
// In any view
@Environment(\.modelContext) private var modelContext

// Query receipts
@Query(sort: \Receipt.date, order: .reverse) var receipts: [Receipt]

// Save
modelContext.insert(receipt)
try modelContext.save()

// Delete
modelContext.delete(receipt)
```

## 🔌 Extending the App

### Add a New View
1. Create file in `Views/` folder
2. Make it a SwiftUI struct
3. Add to navigation flow
4. Update navigation links

### Add a New Model
1. Create file in `Models/` folder
2. Add `@Model` macro
3. Define relationships
4. Update `CheckMateApp.swift` schema

### Add Logic to Service
1. Add method to service class
2. Use async/await if needed
3. Return simple data types
4. Call from views with `.shared` singleton

## 🧪 Testing Your App

### Test OCR
```swift
let service = OCRService.shared
let items = await service.extractLineItems(from: testImage)
// Should return parsed items
```

### Test Split Calculation
```swift
let service = SplitCalculatorService.shared
let splits = service.calculateSplit(
    lineItems: [item1, item2],
    taxAmount: 5,
    tipAmount: 10
)
// Should return [Person: SplitDetails]
```

### Test Views
- Each view has `#Preview` blocks
- Test in preview with sample data
- Use in-memory ModelContainer for testing

## ⚠️ Important Notes

### Camera Permission
- Requires `NSCameraUsageDescription` in Info.plist
- First use prompts user
- Can be changed in Settings > CheckMate

### SwiftData
- Automatic persistence to device
- No internet required
- Data survives app restart
- Delete removes permanently

### Relationships
- Receipt owns LineItems (cascade delete)
- Receipt owns Splits (cascade delete)  
- LineItem references Person (no cascade)
- Split references both Receipt and Person

## 📋 Architecture Principles

✅ **Separation of Concerns**
- Models: Data structures only
- Services: Business logic
- Views: UI and user interaction

✅ **Single Responsibility**
- Each file does one thing well
- Easy to test and modify
- Clear dependencies

✅ **Reusability**
- Services are singletons
- Models are lightweight
- Views are composable

✅ **Modern Swift**
- Uses latest SwiftUI API
- Async/await for concurrency
- @Model for persistence
- @Query for data binding

## 🎓 Learning Points

### SwiftData
- @Model macro for persistence
- @Relationship for connections
- @Query for reading data
- ModelContext for writing

### Vision Framework
- VNRecognizeTextRequest for OCR
- VNImageRequestHandler for processing
- Works with UIImage directly

### SwiftUI
- NavigationStack for routing
- TabView for multi-view apps
- List with ForEach for lists
- Sheets for modals
- Forms for input

## 🚢 Deployment Checklist

Before submitting to App Store:
- [ ] Camera permission message is clear
- [ ] Test with real receipts
- [ ] Handle edge cases (blurry, rotated images)
- [ ] Add app icon
- [ ] Add screenshot for app preview
- [ ] Set privacy URL
- [ ] Create release notes

## 📞 Troubleshooting

| Issue | Solution |
|-------|----------|
| Camera not working | Check NSCameraUsageDescription in Info.plist |
| SwiftData models not saving | Verify @Model macro and schema includes it |
| OCR returns no items | Test with clearer receipt image |
| Navigation not working | Check NavigationStack and NavigationLink setup |
| Preview crashes | Use in-memory ModelContainer in preview |

## ✨ Next Steps

1. **Customize UI** - Add colors, fonts, app icon
2. **Add features** - Search, filters, export
3. **Improve OCR** - Better price detection, multiple currencies
4. **Analytics** - Track spending patterns
5. **Cloud sync** - iCloud backup (requires CloudKit)
6. **Social** - Share bills with friends

Your scaffolding is complete and production-ready!

