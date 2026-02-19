// QUICK_START.md
// CheckMate Receipt Scanner - Quick Start Guide

# ScanView Quick Start Guide

## 🎯 What Was Built?

A complete receipt scanning system for iOS 17+ that:
1. Captures photos via camera or photo library
2. Parses receipt text using Vision framework OCR
3. Extracts line items and prices automatically
4. Allows manual editing of parsed results
5. Saves receipts to SwiftData persistent storage

## 📱 How to Use the App

### First Time Setup

1. **Open Xcode** and select the CheckMate target
2. **Go to Info tab** and add:
   - Key: `NSCameraUsageDescription`
   - Value: `CheckMate needs camera access to scan receipts`
3. **Build and Run** (⌘R)

### Using the Scanner

1. **Tap "Scan" tab** at the bottom (camera icon)
2. **Choose your method:**
   - Tap "Take Photo" to use camera (will request permission)
   - Tap "Choose from Library" to select existing image
3. **Review the image** in the preview
4. **Tap "Scan Receipt"** to extract items
5. **Edit in ReviewReceiptView:**
   - Tap any item to edit
   - Tap + to add new items
   - See running total update
6. **Tap "Save"** to store receipt
7. **View in History tab** to see all receipts

## 📂 File Structure

```
CheckMate/
├── OCRService.swift          # Text extraction & parsing
├── ScanView.swift            # Camera & photo selection UI
├── ReviewReceiptView.swift   # Edit & save results
├── Receipt.swift             # SwiftData model
├── CheckMateApp.swift        # Updated with Receipt model
├── ContentView.swift         # Updated with tabs
└── Item.swift               # Existing (unchanged)
```

## 🔌 How Each File Works

### OCRService.swift
```swift
// Extract text from image
let items = await OCRService.shared.extractLineItems(from: image)
// Returns: [LineItem] with name, price, quantity
```

### ScanView.swift
```swift
// Wraps UIImagePickerController for camera/library access
// Handles camera permission checking
// Navigates to ReviewReceiptView when scan completes
```

### ReviewReceiptView.swift
```swift
// Display & edit parsed items
// Calculate totals
// Save to SwiftData
```

### Receipt.swift
```swift
@Model
final class Receipt {
    var date: Date
    var total: Double
    var itemCount: Int
    var notes: String
}
```

### CheckMateApp.swift
```swift
// Added Receipt to schema:
let schema = Schema([Item.self, Receipt.self])
```

### ContentView.swift
```swift
// Now has 2 tabs:
// [Scan] - Uses ScanView
// [History] - Shows receipts + items
```

## 🔐 Permissions

Required in Info.plist:
```xml
<key>NSCameraUsageDescription</key>
<string>CheckMate needs camera access to scan receipts</string>
```

App will request camera permission first time "Take Photo" is tapped.

## 🚀 Key Features

| Feature | File | How It Works |
|---------|------|------------|
| Camera Access | ScanView | UIImagePickerController with .camera sourceType |
| Photo Library | ScanView | UIImagePickerController with .photoLibrary sourceType |
| Text Recognition | OCRService | Vision.VNRecognizeTextRequest |
| Price Extraction | OCRService | Regex pattern: `[$€£...]?\d+\.\d{2}` |
| Item Editing | ReviewReceiptView | Form with TextField, Stepper |
| Data Storage | Receipt | SwiftData @Model with @Query in ContentView |
| Persistence | CheckMateApp | SwiftData ModelContainer |

## 💡 Example: How OCR Works

```
Input Image (receipt photo)
        ↓
Vision Framework analyzes pixels
        ↓
Extracts text: "Milk    3.99"
                "Bread   2.49"
        ↓
OCRService parses lines
        ↓
Regex matches prices: 3.99, 2.49
        ↓
Creates LineItem objects
        ↓
Returns: [LineItem(name: "Milk", price: 3.99, quantity: 1), ...]
```

## 🎨 UI Hierarchy

```
ScanView (Main tab)
├── Preview area
├── Camera button → ImagePicker (camera)
├── Library button → ImagePicker (library)
└── Scan button → ReviewReceiptView
                    └── List of editable items
                        ├── LineItemRow
                        └── Total
```

## 🔄 Data Flow

```
User takes photo
    ↓
ImagePicker.Coordinator returns UIImage
    ↓
ScanView stores in @State selectedImage
    ↓
User taps "Scan Receipt"
    ↓
Call OCRService.extractLineItems(image) async
    ↓
Get back [LineItem]
    ↓
Navigate to ReviewReceiptView with items
    ↓
User edits items (add/remove/modify)
    ↓
User taps "Save"
    ↓
Create Receipt model with totals
    ↓
Insert into modelContext
    ↓
Saved to SwiftData database
    ↓
Appears in History tab
```

## 🧩 Integration Points

### With Existing Code
- ✅ Uses Item model (unchanged)
- ✅ Uses existing CheckMateApp SwiftData setup
- ✅ Uses existing ContentView
- ✅ ItemContainer automatically includes Receipt model

### With SwiftData
```swift
// In any view:
@Environment(\.modelContext) private var modelContext
@Query private var receipts: [Receipt]

// Items are automatically saved:
modelContext.insert(receipt)
try modelContext.save()
```

## 🐛 Troubleshooting

| Problem | Solution |
|---------|----------|
| Camera permission not requested | Add NSCameraUsageDescription to Info.plist |
| App crashes on camera button | Uninstall app, rebuild, try again |
| OCR not recognizing text | Use clearer receipt image, better lighting |
| Items not saved | Check modelContext isn't nil, call save() |
| Photo library picker shows blank | Try simulator Simulator > Hardware > Keyboard and trust camera |

## 🔗 Where to Find Things

- **Camera logic**: ScanView `takePhoto()` → `requestCameraPermission()`
- **OCR parsing**: OCRService `parseLineItem()` → regex patterns
- **Image picking**: ImagePicker struct & Coordinator class
- **Data saving**: ReviewReceiptView `saveReceipt()` method
- **Display results**: ReviewReceiptView Form with items List

## 💾 Database Schema

### Receipt Table (SwiftData)
| Field | Type | Notes |
|-------|------|-------|
| date | Date | When receipt was scanned |
| total | Double | Sum of all items |
| itemCount | Int | Number of line items |
| notes | String | User's optional notes |

Items are stored in app memory during editing, then summary saved as Receipt.

## 📚 Code Examples

### Use OCRService
```swift
let service = OCRService.shared
let items = await service.extractLineItems(from: uiImage)
```

### Check Camera Permission
```swift
let status = AVCaptureDevice.authorizationStatus(for: .video)
if status == .authorized {
    // Can use camera
}
```

### Save Receipt
```swift
let receipt = Receipt(date: Date(), total: 25.50, itemCount: 3)
modelContext.insert(receipt)
try modelContext.save()
```

### Query Receipts
```swift
@Query(sort: \.date, order: .reverse) private var receipts: [Receipt]
// Most recent first
```

## ✅ Checklist Before First Run

- [ ] Add camera permission to Info.plist
- [ ] Select CheckMate target in Xcode
- [ ] Build project (⌘B)
- [ ] Run on simulator or device (⌘R)
- [ ] Grant camera permission when prompted
- [ ] Try taking a photo of a receipt
- [ ] Verify items appear in ReviewReceiptView
- [ ] Edit and save a receipt
- [ ] Check History tab shows saved receipt

