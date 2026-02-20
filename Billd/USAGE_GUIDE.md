# Quick Start Guide: Using the Optimized Receipt Scanner

## 🚀 For Users

### Scanning a Receipt

1. **Open the app** and tap "Scan Receipt"
2. The **Document Scanner** opens automatically
3. **Position your receipt** in the frame
   - Green border appears when receipt is detected
   - Camera auto-corrects perspective
4. **Tap the capture button** when ready
5. Review the preview and **tap "Use Scan"**
6. App processes the image (takes 1-3 seconds)
7. **Review extracted data**:
   - Restaurant name
   - All items with quantities and prices
   - Tax, tip, discount amounts
   - Total
8. **Make corrections** if needed or tap "Continue"
9. **Assign items** to people and split the bill

### Tips for Best Results

✅ **DO:**
- Use good lighting (natural light is best)
- Flatten the receipt as much as possible
- Make sure all text is visible in frame
- Let VisionKit auto-detect edges

❌ **DON'T:**
- Take photos in dim lighting
- Scan heavily crumpled receipts
- Rush the capture (let auto-detection work)
- Scan receipts with torn-off sections

### Troubleshooting

**Problem:** "No items detected"
- **Solution:** Retake photo with better lighting
- Try flattening receipt more
- Ensure receipt text is crisp and readable

**Problem:** "Totals don't match"
- **Solution:** Review the extracted items
- Check for duplicate entries
- Verify quantities are correct
- Manually edit if needed

**Problem:** "Wrong restaurant name"
- **Solution:** Simply edit the name field
- App learns from your corrections

---

## 💻 For Developers

### Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                   ScanView                      │
│  • Camera interface                             │
│  • User flow coordination                       │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│           VNDocumentCameraViewController        │
│  • Auto edge detection                          │
│  • Perspective correction                       │
│  • Image enhancement                            │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│            ImagePreprocessor                    │
│  • Grayscale conversion                         │
│  • Contrast enhancement                         │
│  • Sharpening                                   │
│  • Noise reduction                              │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│               OCRService                        │
│  • Vision OCR (text extraction)                 │
│  • Apple Intelligence parsing (iOS 26+)         │
│  • Regex fallback parsing                       │
│  • Validation & error detection                 │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│             ParsedReceipt                       │
│  • Restaurant name                              │
│  • Line items (name, unit price, quantity)      │
│  • Subtotal, tax, tip, discount, total          │
└─────────────────────────────────────────────────┘
```

### Key APIs

#### 1. Scan a Receipt

```swift
// In your view
@State private var selectedImage: UIImage?
@State private var parsedReceipt: ParsedReceipt?

// Scan with document scanner
.fullScreenCover(isPresented: $showDocumentScanner) {
    DocumentCameraView { scannedImages in
        selectedImage = scannedImages.first
        processReceipt()
    }
}

// Process the image
func processReceipt() {
    Task {
        let receipt = await OCRService.shared.extractReceiptData(from: selectedImage!)
        parsedReceipt = receipt
    }
}
```

#### 2. Validate Results

```swift
func validateReceipt(_ receipt: ParsedReceipt) -> (isValid: Bool, error: String?) {
    // Check for items
    guard !receipt.items.isEmpty else {
        return (false, "No items detected")
    }
    
    // Validate totals
    let itemsTotal = receipt.items.reduce(0.0) { 
        $0 + ($1.price * Double($1.quantity)) 
    }
    
    if let total = receipt.total {
        let calculatedTotal = (receipt.subtotal ?? itemsTotal) + 
                              (receipt.tax ?? 0) + 
                              (receipt.tip ?? 0) - 
                              (receipt.discount ?? 0)
        
        let difference = abs(total - calculatedTotal)
        if difference > (total * 0.01) && difference > 0.50 {
            return (true, "Totals may not match. Please verify.")
        }
    }
    
    return (true, nil)
}
```

#### 3. Create Receipt Model

```swift
func createReceipt(from parsed: ParsedReceipt, restaurantName: String) -> Receipt {
    // Calculate subtotal from items
    let itemsSubtotal = parsed.items.reduce(0.0) { 
        $0 + ($1.price * Double($1.quantity)) 
    }
    
    let receipt = Receipt(
        restaurantName: restaurantName,
        subtotal: parsed.subtotal ?? itemsSubtotal,
        tax: parsed.tax ?? 0,
        tip: parsed.tip ?? 0,
        discount: parsed.discount ?? 0
    )
    
    // Add line items (store UNIT price, not total)
    for item in parsed.items {
        receipt.lineItems.append(
            LineItem(
                name: item.name, 
                price: item.price,      // Unit price
                quantity: item.quantity  // Quantity
            )
        )
    }
    
    receipt.updateTotal()
    return receipt
}
```

### Data Models

#### ParsedLineItem
```swift
struct ParsedLineItem {
    var name: String        // "Fried Rice"
    var price: Double       // 25.00 (UNIT price)
    var quantity: Int = 1   // 4
}

// Total price calculation:
let totalPrice = price * Double(quantity)  // 25.00 × 4 = 100.00
```

#### ParsedReceipt
```swift
struct ParsedReceipt {
    var restaurantName: String?
    var items: [ParsedLineItem]
    var subtotal: Double?    // Sum of all item totals
    var tax: Double?         // Sales tax
    var tip: Double?         // Gratuity
    var discount: Double?    // Discounts/promos
    var total: Double?       // Final amount
}

// Validation:
// items.sum(price × qty) ≈ subtotal
// subtotal + tax + tip - discount ≈ total
```

### Customization Options

#### Adjust OCR Settings

```swift
// In OCRService.extractReceiptData()
let request = VNRecognizeTextRequest { req, _ in
    // Handle results
}

// Customize these:
request.recognitionLevel = .accurate      // or .fast
request.recognitionLanguages = ["en-US"]  // Add more languages
request.usesLanguageCorrection = true     // Enable/disable
request.minimumTextHeight = 0.03          // Adjust for small text
```

#### Customize Image Enhancement

```swift
// In ImagePreprocessor.enhanceForOCR()

// Adjust contrast (default: 1.2)
contrastFilter.setValue(1.5, forKey: kCIInputContrastKey)

// Adjust sharpness (default: 0.7)
sharpenFilter.setValue(1.0, forKey: kCIInputSharpnessKey)

// Adjust noise reduction (default: 0.02)
noiseFilter.setValue(0.05, forKey: "inputNoiseLevel")
```

#### Customize Validation Thresholds

```swift
// In ScanView.validateReceipt()

// Price range (default: $0.01 - $500.00)
if item.price < 0.01 || item.price > 1000.00 {
    // Flag as suspicious
}

// Total difference tolerance (default: 1% or $0.50)
let tolerance = max(total * 0.02, 1.00)  // Increase to 2% or $1
if difference > tolerance {
    // Show warning
}
```

### AI Parsing (iOS 26+)

The AI parsing uses Apple's Foundation Models framework:

```swift
@available(iOS 26.0, *)
private func parseReceiptWithAI(from lines: [String]) async -> ParsedReceipt {
    let session = LanguageModelSession(instructions: """
        You are an expert receipt parser...
        [detailed instructions]
    """)
    
    let response = try await session.respond(
        to: "Extract all information from this receipt:\n\n\(fullText)",
        generating: ReceiptData.self
    )
    
    return transformToReceipt(response.content)
}
```

**Key features:**
- Natural language understanding of receipt structure
- Context-aware quantity and price extraction
- Self-validation against mathematical constraints
- Handles variations in receipt formats

### Error Handling

```swift
// OCR Service errors
do {
    try handler.perform([request])
} catch {
    print("OCR Error: \(error)")
    // Fall back to manual entry
}

// AI parsing errors
do {
    let response = try await session.respond(...)
} catch {
    print("AI parsing failed: \(error)")
    // Fall back to regex parsing
}

// Validation errors
let validation = validateReceipt(receipt)
if !validation.isValid {
    // Show alert with validation.error
    // Allow manual correction
}
```

### Testing

Run the test suite:

```swift
import Testing
@testable import Billd

@Test("Receipt total calculation")
func testReceiptTotal() {
    let items = [
        ParsedLineItem(name: "Burger", price: 10.00, quantity: 2),
        ParsedLineItem(name: "Fries", price: 5.00, quantity: 1)
    ]
    
    let total = items.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
    #expect(total == 25.00)
}
```

See `ReceiptScanningTests.swift` for complete test suite.

### Performance Considerations

**OCR Processing:**
- Typical: 1-2 seconds for standard receipt
- Large receipt (20+ items): 2-3 seconds
- Optimization: Process on background queue

**AI Parsing (iOS 26+):**
- Typical: 2-4 seconds
- Depends on receipt complexity
- Runs locally, no network required

**Image Preprocessing:**
- Typical: 100-300ms
- Minimal impact on UX

### Best Practices

1. **Always validate user-facing data**
   ```swift
   let validation = validateReceipt(receipt)
   if !validation.isValid {
       showWarning(validation.error)
   }
   ```

2. **Store unit prices, not totals**
   ```swift
   // ✅ CORRECT
   LineItem(name: "Item", price: 25.00, quantity: 4)
   
   // ❌ WRONG
   LineItem(name: "Item", price: 100.00, quantity: 4)
   ```

3. **Provide editing UI**
   - Users should be able to correct mistakes
   - Make it easy to add/remove items
   - Show clear before/after comparisons

4. **Log for improvement**
   ```swift
   print("✨ AI extracted: \(receipt.items.count) items")
   print("⚠️ Validation warning: \(error)")
   ```

5. **Handle edge cases gracefully**
   - No items detected → manual entry
   - Totals mismatch → show warning
   - Poor image quality → retry prompt

### Future Enhancements

Consider adding:
- [ ] Receipt history with ML improvement
- [ ] Custom receipt templates per restaurant
- [ ] Multi-currency support
- [ ] Batch scanning (multiple receipts)
- [ ] Export to CSV/PDF
- [ ] Integration with accounting software

---

## 📊 Debugging Tips

### Enable Verbose Logging

```swift
// In OCRService
print("📸 Preprocessing image...")
print("📝 OCR extracted \(lines.count) lines")
print("✨ AI extracted: \(items.count) items")
print("⚠️ Validation warning: \(error)")
```

### Inspect Parsed Data

```swift
print("--- PARSED RECEIPT ---")
print("Restaurant: \(receipt.restaurantName ?? "none")")
print("Items:")
for item in receipt.items {
    print("  \(item.quantity)x \(item.name) @ $\(item.price) = $\(item.price * Double(item.quantity))")
}
print("Subtotal: $\(receipt.subtotal ?? 0)")
print("Tax: $\(receipt.tax ?? 0)")
print("Tip: $\(receipt.tip ?? 0)")
print("Discount: $\(receipt.discount ?? 0)")
print("Total: $\(receipt.total ?? 0)")
print("---")
```

### Test with Sample Receipts

Create test receipts with known values:

```swift
let testReceipt = ParsedReceipt(
    restaurantName: "Test Restaurant",
    items: [
        ParsedLineItem(name: "Burger", price: 10.00, quantity: 2),
        ParsedLineItem(name: "Fries", price: 3.50, quantity: 2),
        ParsedLineItem(name: "Drink", price: 2.00, quantity: 2)
    ],
    subtotal: 31.00,
    tax: 3.10,
    tip: 5.00,
    discount: 0.0,
    total: 39.10
)

// Validate
let itemsTotal = testReceipt.items.reduce(0.0) { 
    $0 + ($1.price * Double($1.quantity)) 
}
assert(itemsTotal == 31.00, "Items should sum to subtotal")

let calculatedTotal = 31.00 + 3.10 + 5.00
assert(calculatedTotal == 39.10, "Total should be correct")
```

---

## 🎓 Additional Resources

- **VisionKit Documentation**: [Apple Developer](https://developer.apple.com/documentation/visionkit)
- **Vision Framework**: [Text Recognition](https://developer.apple.com/documentation/vision/recognizing_text_in_images)
- **Foundation Models**: [Apple Intelligence](https://developer.apple.com/documentation/foundationmodels)
- **Swift Testing**: [Testing Framework](https://developer.apple.com/documentation/testing)

---

## 📧 Support

If you encounter issues:
1. Check the console logs for error messages
2. Review the validation warnings
3. Test with different receipt formats
4. Collect edge cases for improvement

Happy scanning! 🧾✨
