//
//  ScanView.swift
//  Billd
//
//  Created by Syam Shukla on 2/18/26.
//

import SwiftUI
import VisionKit
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ScanView: View {
    /// Called after a receipt is created and saved. HomeView uses this to navigate.
    var onReceiptCreated: ((Receipt) -> Void)?

    @State private var showDocumentScanner = false
    @State private var libraryPickerPresented = false
    @State private var selectedImage: UIImage?
    @State private var isProcessing = false
    @State private var hasProcessed = false  // Tracks if current image has been processed (prevents auto-reprocessing same image)
    @State private var showCameraPermissionAlert = false
    @State private var parsedReceipt: ParsedReceipt?
    @State private var editableItems: [ParsedLineItem] = []   // User-correctable item list
    @State private var showRestaurantInput = false
    @State private var restaurantName = ""
    @State private var createdReceipt: Receipt?
    @State private var showItemAssign = false
    @State private var parseError: String?
    @State private var showParseError = false

    private var aiAvailable: Bool {
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability {
                return true
            }
        }
        return false
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                // AI Status Banner
                if aiAvailable {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.appAccent)
                        Text("Smart scanning powered by Apple Intelligence")
                            .font(.caption)
                            .foregroundStyle(.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.elevatedCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }

                // Preview / placeholder
                Group {
                    if let image = selectedImage {
                        // No background card — the image is its own container.
                        // Avoids the dark grey bleed-through that appears around
                        // landscape images when the card height exceeds the image height.
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.cardBackground)
                            VStack(spacing: 14) {
                                Image(systemName: "doc.viewfinder.fill")
                                    .font(.system(size: 52))
                                    .foregroundStyle(.appAccent)
                                Text("Scan a Receipt")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                Text("Use the document scanner for best results")
                                    .font(.subheadline)
                                    .foregroundStyle(.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(24)
                        }
                        .frame(maxHeight: 280)
                    }
                }
                .padding(.horizontal, 16)

                // Buttons
                VStack(spacing: 12) {
                    // Primary: VisionKit document scanner
                    actionButton(
                        title: "Scan Receipt",
                        icon: "doc.viewfinder.fill",
                        color: .appAccent,
                        action: { showDocumentScanner = true }
                    )

                    actionButton(
                        title: "Choose from Library",
                        icon: "photo.fill",
                        color: Color.elevatedCard,
                        foreground: .white,
                        action: { libraryPickerPresented = true }
                    )

                    if selectedImage != nil {
                        actionButton(
                            title: isProcessing ? "Processing…" : "Process Image",
                            icon: isProcessing ? nil : "sparkle.magnifyingglass",
                            color: Color(hex: "34C759"),
                            isLoading: isProcessing,
                            action: scanReceipt
                        )
                        .disabled(isProcessing)
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.top, 8)
        }
        .navigationTitle("Scan Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.textSecondary)
            }
        }
        // VisionKit Document Scanner
        .fullScreenCover(isPresented: $showDocumentScanner) {
            if #available(iOS 16.0, *), VNDocumentCameraViewController.isSupported {
                DocumentCameraView { scannedImages in
                    guard let firstImage = scannedImages.first else { return }
                    selectedImage = normalizeOrientation(firstImage)
                    hasProcessed = false
                    showDocumentScanner = false
                    scanReceipt()
                }
                .ignoresSafeArea()
            } else {
                // Fallback to basic camera
                CameraView { capturedImage in
                    selectedImage = normalizeOrientation(capturedImage)
                    hasProcessed = false
                    showDocumentScanner = false
                    scanReceipt()
                }
                .ignoresSafeArea()
            }
        }
        // Photo library fallback
        .sheet(isPresented: $libraryPickerPresented) {
            ImagePicker(image: $selectedImage, sourceType: .photoLibrary)
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            // Reset hasProcessed when a new image is selected
            if newValue != nil && oldValue != newValue {
                hasProcessed = false
            }
        }
        .sheet(isPresented: $showRestaurantInput) {
            NavigationStack {
                RestaurantInputView(
                    restaurantName: $restaurantName,
                    editableItems: $editableItems,
                    parsedReceipt: parsedReceipt,
                    onSave: { createReceipt() }
                )
            }
        }
        .navigationDestination(isPresented: $showItemAssign) {
            if let receipt = createdReceipt {
                ItemAssignView(receipt: receipt, onDone: { dismiss() })
            } else {
                EmptyView()
            }
        }
        .alert("Camera Permission Required", isPresented: $showCameraPermissionAlert) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Billd needs camera access to scan receipts.")
        }
        .alert("Parsing Issue", isPresented: $showParseError) {
            Button("OK") {}
        } message: {
            Text(parseError ?? "Could not parse receipt. You can add items manually.")
        }
    }

    // MARK: - Button builder

    @ViewBuilder
    private func actionButton(
        title: String,
        icon: String?,
        color: Color,
        foreground: Color = .white,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let icon {
                    Image(systemName: icon)
                        .fontWeight(.semibold)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(color)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Actions

    private func scanReceipt() {
        guard let image = selectedImage else { return }
        // Prevent double-tap while processing
        guard !isProcessing else { return }

        isProcessing = true
        hasProcessed = true

        Task {
            let receipt = await OCRService.shared.extractReceiptData(from: image)
            await MainActor.run {
                // Validate the parsed receipt
                let validation = validateReceipt(receipt)
                if !validation.isValid {
                    parseError = validation.error
                    showParseError = true
                    print("⚠️ Validation warning: \(validation.error ?? "unknown")")
                }

                parsedReceipt = receipt
                editableItems = receipt.items    // seed the editable list from parsed result
                // Pre-fill restaurant name if available
                restaurantName = receipt.restaurantName ?? ""
                isProcessing = false
                showRestaurantInput = true
            }
        }
    }

    // Validate that the receipt totals make sense
    private func validateReceipt(_ receipt: ParsedReceipt) -> (isValid: Bool, error: String?) {
        // Check if we have items
        guard !receipt.items.isEmpty else {
            return (false, "No items detected on receipt. You can add them manually.")
        }

        // Check if prices are reasonable
        let itemsTotal = receipt.items.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }

        // If we have a receipt total, validate it matches
        if let total = receipt.total {
            let subtotal = receipt.subtotal ?? itemsTotal
            let tax = receipt.tax ?? 0
            let tip = receipt.tip ?? 0
            let discount = receipt.discount ?? 0
            let calculatedTotal = subtotal + tax + tip - discount
            let difference = abs(total - calculatedTotal)

            // Allow 1% margin for rounding
            if difference > (total * 0.01) && difference > 0.50 {
                return (true, "Receipt totals may not match. Please verify amounts.")
            }
        }

        // Check for unreasonably priced items
        for item in receipt.items {
            if item.price < 0.01 {
                return (true, "Some items have very low prices. Please verify.")
            }
            if item.price > 500.00 {
                return (true, "Some items have very high prices. Please verify.")
            }
        }

        return (true, nil)
    }

    private func createReceipt() {
        guard let parsed = parsedReceipt else { return }

        // Subtotal: use the user-corrected items total if the parsed subtotal is missing,
        // or if the user edited items such that the parsed subtotal no longer matches.
        let userItemsTotal = editableItems.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
        let subtotal  = parsed.subtotal  ?? userItemsTotal
        let tax       = parsed.tax       ?? 0
        let tip       = parsed.tip       ?? 0
        let discount  = parsed.discount  ?? 0

        let receipt = Receipt(
            restaurantName: restaurantName,
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            discount: discount
        )

        // Use the user-reviewed/corrected item list — not the raw parsed list
        for item in editableItems where !item.name.trimmingCharacters(in: .whitespaces).isEmpty {
            receipt.lineItems.append(
                LineItem(name: item.name, price: item.price, quantity: item.quantity)
            )
        }

        // If OCR captured the printed total, use it directly — it is the source of truth
        // and accounts for any charges (service fees, rounding) we may have missed.
        // Otherwise recompute from components.
        if let parsedTotal = parsed.total {
            receipt.total = parsedTotal
        } else {
            receipt.updateTotal()
        }

        print("✅ Receipt created: \(receipt.lineItems.count) items, total: $\(String(format: "%.2f", receipt.total))")

        modelContext.insert(receipt)
        try? modelContext.save()
        onReceiptCreated?(receipt)
        createdReceipt = receipt
        showItemAssign = true
    }

    // MARK: - Image orientation fix

    /// Normalizes image orientation to .up so the preview always shows portrait receipts correctly.
    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return normalized
    }
}

// MARK: - DocumentCameraView (VisionKit Document Scanner)

@available(iOS 13.0, *)
struct DocumentCameraView: UIViewControllerRepresentable {
    let onCapture: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onCapture: ([UIImage]) -> Void

        init(onCapture: @escaping ([UIImage]) -> Void) {
            self.onCapture = onCapture
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                images.append(image)
            }

            controller.dismiss(animated: true) {
                self.onCapture(images)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("Document scanner error: \(error)")
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - CameraView (Simple one-shot camera)

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void

        init(onCapture: @escaping (UIImage) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                picker.dismiss(animated: true) {
                    self.onCapture(image)
                }
            } else {
                picker.dismiss(animated: true)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - ImagePicker (library fallback)

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(image: $image) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        @Binding var image: UIImage?
        init(image: Binding<UIImage?>) { _image = image }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - RestaurantInputView (editable review + correction)

struct RestaurantInputView: View {
    @Binding var restaurantName: String
    @Binding var editableItems: [ParsedLineItem]
    let parsedReceipt: ParsedReceipt?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    // MARK: Computed helpers

    private var itemsTotal: Double {
        editableItems.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
    }

    /// How far off the user's items are from the printed subtotal (nil if no subtotal).
    private var mathDiscrepancy: Double? {
        guard let sub = parsedReceipt?.subtotal, sub > 0 else { return nil }
        return abs(itemsTotal - sub)
    }

    private var mathIsGood: Bool {
        guard let diff = mathDiscrepancy,
              let sub  = parsedReceipt?.subtotal else { return true }
        return diff <= max(sub * 0.05, 0.50)  // within 5% or $0.50
    }

    private var hasReceiptDetails: Bool {
        guard let r = parsedReceipt else { return false }
        return r.subtotal != nil || r.tax != nil || r.tip != nil || r.discount != nil || r.total != nil
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            Form {
                restaurantSection
                itemsEditSection
                if hasReceiptDetails { receiptDetailsSection }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Review Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.textSecondary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Continue") { onSave(); dismiss() }
                    .foregroundStyle(.appAccent)
                    .fontWeight(.semibold)
                    .disabled(restaurantName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Restaurant section

    private var restaurantSection: some View {
        Section {
            TextField("Restaurant Name", text: $restaurantName)
                .foregroundStyle(.white)
            if let name = parsedReceipt?.restaurantName, !name.isEmpty {
                Text("Auto-detected from receipt")
                    .font(.caption).foregroundStyle(.appAccent)
            }
        } header: { Text("Restaurant") }
        .listRowBackground(Color.cardBackground)
    }

    // MARK: - Editable items section

    private var itemsEditSection: some View {
        Section {
            // Math check row — shows whether items add up correctly
            mathStatusRow

            if editableItems.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.appWarning)
                    Text("No items detected — add them below")
                        .font(.caption).foregroundStyle(.appWarning)
                }
            } else {
                ForEach(editableItems.indices, id: \.self) { idx in
                    editableItemRow(index: idx)
                }
                .onDelete { offsets in editableItems.remove(atOffsets: offsets) }
            }

            // Add Item row
            Button(action: { editableItems.append(ParsedLineItem(name: "", price: 0)) }) {
                Label("Add Item", systemImage: "plus.circle.fill")
                    .foregroundStyle(.appAccent)
            }
        } header: {
            HStack {
                Text("Items")
                Spacer()
                if !editableItems.isEmpty {
                    Text("Swipe to delete")
                        .font(.caption2)
                        .foregroundStyle(.textSecondary)
                        .textCase(nil)
                }
            }
        }
        .listRowBackground(Color.cardBackground)
    }

    /// One editable row per item — name and price are inline text fields.
    private func editableItemRow(index: Int) -> some View {
        HStack(spacing: 10) {
            TextField("Item name", text: $editableItems[index].name)
                .foregroundStyle(.white)
            Spacer()
            Text("$").foregroundStyle(.textSecondary).font(.caption)
            TextField(
                "0.00",
                value: $editableItems[index].price,
                format: .number.precision(.fractionLength(2))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.textSecondary)
            .frame(width: 68)
        }
    }

    /// Green check when items ≈ subtotal; orange warning with the gap amount otherwise.
    private var mathStatusRow: some View {
        HStack(spacing: 6) {
            if let sub = parsedReceipt?.subtotal {
                Image(systemName: mathIsGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(mathIsGood ? Color.green : Color.appWarning)
                    .font(.caption)
                Text("Items: \(String(format: "$%.2f", itemsTotal))")
                    .font(.caption).foregroundStyle(.textSecondary)
                Text("·").foregroundStyle(.textSecondary).font(.caption)
                Text("Subtotal: \(String(format: "$%.2f", sub))")
                    .font(.caption).foregroundStyle(.textSecondary)
                if !mathIsGood, let diff = mathDiscrepancy {
                    Spacer()
                    Text("Δ \(String(format: "$%.2f", diff))")
                        .font(.caption).fontWeight(.medium).foregroundStyle(.appWarning)
                }
            } else {
                Text("\(editableItems.count) item\(editableItems.count == 1 ? "" : "s") · \(String(format: "$%.2f", itemsTotal)) total")
                    .font(.caption).foregroundStyle(.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Receipt details section (read-only — these come from the printed receipt)

    private var receiptDetailsSection: some View {
        Section {
            if let r = parsedReceipt {
                if let v = r.subtotal  { receiptRow(label: "Subtotal",  amount: v) }
                if let v = r.discount  { receiptRow(label: "Discount",  amount: v, prefix: "-", color: .green) }
                if let v = r.tax       { receiptRow(label: "Tax",       amount: v) }
                if let v = r.tip       { receiptRow(label: "Tip",       amount: v) }
                if let v = r.total     { receiptRow(label: "Total",     amount: v, bold: true, color: .appAccent) }
            }
        } header: { Text("Receipt Details") }
        .listRowBackground(Color.cardBackground)
    }

    private func receiptRow(label: String, amount: Double,
                            prefix: String = "", bold: Bool = false,
                            color: Color = .textSecondary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white)
                .fontWeight(bold ? .semibold : .regular)
            Spacer()
            Text(prefix + String(format: "$%.2f", amount))
                .foregroundStyle(color)
                .fontWeight(bold ? .semibold : .regular)
        }
    }
}

#Preview {
    NavigationStack {
        ScanView()
    }
}
