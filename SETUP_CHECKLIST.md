// SETUP_CHECKLIST.md
// CheckMate Receipt Scanner - Setup Checklist

# ✅ Setup Checklist

## Before You Build

### 1. Camera Permission (REQUIRED)
- [ ] Open CheckMate.xcodeproj in Xcode
- [ ] Select the CheckMate target
- [ ] Go to **Info** tab (top of editor)
- [ ] Click **+** button to add new property
- [ ] Search for "Privacy - Camera Usage Description"
- [ ] Value: `CheckMate needs camera access to scan receipts`
- [ ] Save the changes

**Alternative Method (if Info tab not visible):**
1. Select CheckMate target
2. Build Settings tab
3. Search "Camera"
4. Find "Privacy - Camera Usage Description"
5. Set to: `CheckMate needs camera access to scan receipts`

### 2. Files Verify
- [ ] OCRService.swift ✓ Created
- [ ] ScanView.swift ✓ Created  
- [ ] ReviewReceiptView.swift ✓ Created
- [ ] Receipt.swift ✓ Created
- [ ] CheckMateApp.swift ✓ Updated with Receipt model
- [ ] ContentView.swift ✓ Updated with ScanView tab

### 3. Build & Run
- [ ] Press ⌘B to build
- [ ] Fix any build errors (should be none)
- [ ] Press ⌘R to run
- [ ] App launches successfully

### 4. First Time Camera Use
- [ ] Tap "Scan" tab
- [ ] Tap "Take Photo" button
- [ ] Allow permission prompt appears
- [ ] Tap "Allow" in permission alert
- [ ] Camera app opens (or photo library if "Choose from Library")

### 5. Test Receipt Scanning
- [ ] Take a photo of a receipt (or select one)
- [ ] Image preview appears
- [ ] Tap "Scan Receipt"
- [ ] Processing spinner shows
- [ ] ReviewReceiptView opens with parsed items
- [ ] Items display with prices

### 6. Test Item Editing
- [ ] Tap an item to edit
- [ ] Sheet appears with edit form
- [ ] Change name/price/quantity
- [ ] Tap Save
- [ ] Item updates in list
- [ ] Total recalculates

### 7. Test Saving
- [ ] Verify all items are correct
- [ ] Tap the "Save" button (top right)
- [ ] Returns to ScanView
- [ ] Switch to "History" tab
- [ ] New receipt appears in list
- [ ] Shows correct total

### 8. Verify SwiftData Integration
- [ ] Close and reopen app
- [ ] Go to History tab
- [ ] Receipts still there (data persisted)
- [ ] Delete a receipt
- [ ] Goes away permanently

### 9. Test Permission Denial
- [ ] Go to Settings > CheckMate
- [ ] Toggle Camera permission OFF
- [ ] Close app
- [ ] Reopen app
- [ ] Tap Scan > Take Photo
- [ ] Permission denied alert appears
- [ ] "Settings" button navigates to app settings
- [ ] Try "Choose from Library" (still works)

### 10. Error Cases (Optional)
- [ ] Test with blurry receipt photo
- [ ] Test with sideways/rotated receipt
- [ ] Test with very small text
- [ ] Test with multiple receipts in a row
- [ ] Test rapid add/delete of items

## ✅ All Clear?

If all items are checked:
- ✅ Camera permission properly configured
- ✅ All new files created successfully  
- ✅ SwiftData integration working
- ✅ Receipt scanning functionality complete
- ✅ Data persistence verified
- ✅ Permission handling tested
- ✅ You're ready to use CheckMate!

## 🚀 You're All Set!

Your CheckMate receipt scanner is now fully functional. Features ready:

✓ Scan receipts with camera
✓ Select from photo library
✓ Auto-parse line items with OCR
✓ Edit recognized items
✓ Calculate running totals
✓ Save receipts permanently
✓ View receipt history
✓ Handle permission gracefully

## 📞 Common Issues & Solutions

### Build Fails with "Receipt" not found
**Solution:** Make sure Receipt.swift was created in CheckMate folder (not Tests folder)

### Camera permission not requested on tap
**Solution:** Camera permission must be in Info.plist with exact key:
```
NSCameraUsageDescription
```

### OCR returns empty items
**Solution:** 
- Ensure receipt image is clear and well-lit
- Text should be readable size (10pt+)
- Try different angle or lighting

### Data not persisting after restart
**Solution:** 
- Verify Receipt model was added to CheckMateApp schema
- Check modelContext.save() is called in ReviewReceiptView
- Restart app completely (kill and reopen)

### Permission denied but want to enable camera
**Solution:**
- Settings > CheckMate > Camera > toggle ON
- Or tap "Settings" button in permission alert

## 📝 Notes

- First camera use will prompt permission
- Permission can be changed in Settings anytime
- Photo library doesn't need permission (built into iOS)
- All receipts automatically dated
- Prices stored as Double precision

## 🎉 Success Indicators

You'll know everything works when:

1. **Camera tab loads** with helpful UI
2. **Taking photo** opens camera or library
3. **OCR completes** and shows parsed items
4. **Editing works** smoothly with updates
5. **Saving persists** data (survives app restart)
6. **History shows** all previous receipts
7. **Permissions work** gracefully

Enjoy scanning! 📱✨

