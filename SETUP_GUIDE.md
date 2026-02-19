//
//  SETUP_GUIDE.md
//  CheckMate
//
//  Setup instructions for ScanView implementation
//

# CheckMate ScanView Setup Guide

## Required Privacy Permissions

Since the ScanView requires camera access, you need to add the camera usage description to your Info.plist.

### Method 1: Xcode UI (Recommended)

1. Open your project in Xcode
2. Select the **CheckMate** target
3. Go to the **Info** tab
4. Click the **+** button to add a new property
5. Search for "Privacy - Camera Usage Description"
6. Add the value: `"CheckMate needs camera access to scan receipts"`

### Method 2: Info.plist File

If your Info.plist is not auto-generated, add this key:

```xml
<key>NSCameraUsageDescription</key>
<string>CheckMate needs camera access to scan receipts</string>
```

### Method 3: Build Settings

If using auto-generated Info.plist, you can set it via build settings:

1. Select the **CheckMate** target
2. Go to **Build Settings**
3. Search for "Camera"
4. Set **Privacy - Camera Usage Description** to your desired message

## Framework Requirements

The implementation uses the following frameworks (all included in iOS 17+):

- **SwiftUI**: For UI components
- **Vision**: For OCR text recognition
- **AVFoundation**: For camera permission handling
- **SwiftData**: For data persistence

All frameworks are automatically linked in the project.

## Features Implemented

### 1. **ScanView**
- UIImagePickerController wrapped in UIViewControllerRepresentable
- Camera and photo library selection
- Graceful camera permission handling with user-facing alert
- Image preview before scanning
- Processing indicator during OCR

### 2. **OCRService**
- Vision framework-based text recognition
- Automatic line item parsing from receipts
- Price detection and extraction
- Duplicate removal and noise filtering

### 3. **ReviewReceiptView**
- Display parsed line items
- Edit item names, prices, and quantities
- Add/remove items
- Calculate and display total
- Save receipt to SwiftData

### 4. **Data Models**
- `LineItem`: Struct for parsed receipt items
- `Receipt`: SwiftData model for persisted receipts

## How It Works

### User Flow

1. **Scan**: User opens ScanView tab
2. **Capture**: User takes photo or selects from library
3. **Process**: OCRService parses text and extracts line items
4. **Review**: ReviewReceiptView displays results for editing
5. **Save**: User confirms and receipt is saved to SwiftData

### OSR Recognition Process

1. Image is analyzed using Vision framework
2. Text is extracted with high accuracy
3. Lines are parsed for item names and prices
4. Pattern matching identifies currency amounts
5. Duplicates are removed and noise is filtered

## Integration with SwiftData

The Receipt model is automatically added to SwiftData's schema in CheckMateApp. Receipts are persisted and displayed in the History tab.

To query receipts:
```swift
@Query private var receipts: [Receipt]
```

## Testing

### Test Cases

1. **Camera Permission Denied**: App should show permission alert
2. **Clear Receipt Image**: Should parse items accurately
3. **Blurry Image**: Should handle gracefully
4. **Empty Receipt**: Should show empty item list
5. **Manual Edits**: Should allow full customization

### Test Images

For testing, use:
- Clear receipt photos from digital cameras
- Screenshots of receipt PDFs
- Phone photos taken at various angles

## Troubleshooting

### App Crashes on Camera Access

Make sure the camera permission string is added to Info.plist as described above.

### OCR Not Recognizing Text

- Ensure image is well-lit and clear
- Text should be at least 10pt font
- Try different angles or distances
- Consider using clearer receipt photos

### Permission Not Requested

1. Uninstall the app from simulator/device
2. Rebuild and run
3. Or go to Settings > CheckMate > Camera and reset permissions

## Notes

- iOS 17+ is required for full compatibility
- Vision framework is available on iOS 13+, but iOS 17+ recommended for accuracy
- SwiftUI is compatible with iOS 15+
- SwiftData requires iOS 17+ and macOS 14+

