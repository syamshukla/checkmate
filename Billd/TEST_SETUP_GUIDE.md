# Setting Up Tests in Xcode

## Quick Fix: Delete the Swift Testing Version

The `ReceiptScanningTests.swift` file uses the Swift Testing framework which requires:
- Xcode 16+ 
- Swift 6+
- Proper test target configuration

**Recommended Solution:** Use the XCTest version instead.

### Steps to Fix:

1. **Delete the problematic file:**
   - In Xcode, locate `ReceiptScanningTests.swift`
   - Right-click → Delete → Move to Trash

2. **Add the XCTest version:**
   - Drag `ReceiptScanningTestsXCTest.swift` into your `BilldTests` folder in Xcode
   - Make sure "Add to targets" includes `BilldTests`
   - Click "Finish"

3. **Run tests:**
   - Press `Cmd + U` to run all tests
   - Or click the diamond icon next to individual test methods

---

## Alternative: Set Up Swift Testing (Advanced)

If you want to use the modern Swift Testing framework:

### 1. Check Requirements

- Xcode 16.0 or later
- iOS 18.0+ deployment target (or macOS 15.0+)

### 2. Update Your Test Target

1. Select your project in the navigator
2. Select the `BilldTests` target
3. Go to "Build Phases"
4. In "Link Binary With Libraries", add:
   - `Testing.framework` (if available)

### 3. Update Build Settings

1. Select `BilldTests` target
2. Go to "Build Settings"
3. Search for "Swift Language Version"
4. Set to "Swift 6" or later

### 4. Create Proper Test Target

If you don't have a Swift Testing compatible test target:

1. File → New → Target
2. Choose "Unit Testing Bundle"
3. Product Name: `BilldSwiftTests`
4. Testing Framework: Select "Swift Testing" (if available)
5. Click Finish

### 5. Move Test File

1. Delete `ReceiptScanningTests.swift` from `BilldTests`
2. Add it to the new `BilldSwiftTests` target
3. Ensure it's in the "Compile Sources" phase

---

## Comparison: XCTest vs Swift Testing

### XCTest (Traditional - Recommended for now)

✅ **Pros:**
- Works on all iOS versions
- Widely supported and documented
- Stable and mature
- No setup required

❌ **Cons:**
- More verbose syntax
- Class-based (not as modern)

**Example:**
```swift
import XCTest

class MyTests: XCTestCase {
    func testExample() {
        XCTAssertEqual(2 + 2, 4)
    }
}
```

### Swift Testing (Modern - Future)

✅ **Pros:**
- More concise syntax
- Better parameterized testing
- Struct-based (modern Swift)
- Better error messages

❌ **Cons:**
- Requires Xcode 16+ and Swift 6+
- iOS 18+ deployment target
- Less documentation available

**Example:**
```swift
import Testing

@Suite("My Tests")
struct MyTests {
    @Test("Addition works")
    func testAddition() {
        #expect(2 + 2 == 4)
    }
}
```

---

## Current Status of Your Tests

### Files Created:

1. **`ReceiptScanningTests.swift`** (Swift Testing - CAUSING ERROR)
   - Uses `import Testing`
   - Modern syntax with `@Test` and `#expect`
   - Requires Xcode 16+ and Swift 6+

2. **`ReceiptScanningTestsXCTest.swift`** (XCTest - WORKS EVERYWHERE)
   - Uses `import XCTest`
   - Traditional syntax with `XCTAssert*`
   - Works with current Xcode setup

### Recommendation:

**Use the XCTest version (`ReceiptScanningTestsXCTest.swift`)** because:
- It works immediately with your current setup
- No configuration needed
- Fully functional and comprehensive
- Can be renamed to `ReceiptScanningTests.swift` once you delete the old one

---

## Quick Setup Steps (Recommended)

### Step 1: Clean Up

```bash
# In Terminal, navigate to your project
cd /Users/sam/Documents/Billd/Billd

# Remove the problematic file
rm ReceiptScanningTests.swift

# Rename the XCTest version
mv ReceiptScanningTestsXCTest.swift ReceiptScanningTests.swift
```

### Step 2: Add to Xcode

1. In Xcode, right-click on `BilldTests` folder
2. Select "Add Files to 'Billd'..."
3. Choose `ReceiptScanningTests.swift`
4. Make sure "Add to targets" includes `BilldTests`
5. Click "Add"

### Step 3: Run Tests

```bash
# In Terminal
xcodebuild test -scheme Billd -destination 'platform=iOS Simulator,name=iPhone 15'

# Or in Xcode:
# Press Cmd + U
```

---

## Test Organization

Your test file includes:

### Unit Tests:
- ✅ Line item calculations
- ✅ Receipt total validation
- ✅ Price range validation
- ✅ Quantity handling
- ✅ Edge cases (empty receipts, fractional quantities)

### Integration Tests:
- ✅ End-to-end receipt processing
- ✅ Split calculation validation

### Performance Tests:
- ✅ Large receipt parsing (100 items)
- ✅ Validation speed benchmarks

---

## Troubleshooting

### Error: "No such module 'Billd'"

**Fix:**
1. Make sure `ReceiptScanningTests.swift` is in the `BilldTests` target
2. Check that `@testable import Billd` is correct (use your actual module name)
3. Ensure the main app target builds successfully first

### Error: "Cannot find 'ParsedLineItem' in scope"

**Fix:**
1. Make sure `ParsedLineItem` is defined in your main app target
2. Check that it's marked as `internal` or `public` (not `private`)
3. Verify `@testable import Billd` is present

### Error: "Use of unresolved identifier 'XCTAssertEqual'"

**Fix:**
1. Make sure you have `import XCTest` at the top
2. Ensure the file is in a test target (not the main app target)
3. Check that the test target has `XCTest.framework` linked

---

## Running Specific Tests

### In Xcode:

1. **Run all tests:** `Cmd + U`
2. **Run tests in current file:** Click the diamond next to the class name
3. **Run single test:** Click the diamond next to the test method

### In Terminal:

```bash
# Run all tests
xcodebuild test -scheme Billd -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test class
xcodebuild test -scheme Billd -only-testing:BilldTests/ReceiptScanningTests

# Run specific test method
xcodebuild test -scheme Billd -only-testing:BilldTests/ReceiptScanningTests/testLineItemTotalPrice
```

---

## Next Steps

1. ✅ Delete or replace the Swift Testing version
2. ✅ Add the XCTest version to your test target
3. ✅ Run tests to verify everything works
4. ✅ Add more tests as you develop new features
5. ✅ Set up CI/CD to run tests automatically

---

## Summary

**Immediate Action Required:**

1. Delete `ReceiptScanningTests.swift` (Swift Testing version)
2. Use `ReceiptScanningTestsXCTest.swift` instead
3. Add it to your `BilldTests` target in Xcode
4. Run tests with `Cmd + U`

The XCTest version provides identical test coverage and works with your current Xcode setup! 🎉
