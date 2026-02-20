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
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.cardBackground)
                        .frame(maxHeight: 280)

                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(8)
                    } else {
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
                }
                .padding(.horizontal, 16)

                // Buttons
                VStack(spacing: 12) {
                    // Primary: VisionKit document scanner
                    if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                        actionButton(
                            title: "Scan Receipt (Document Scanner)",
                            icon: "doc.viewfinder.fill",
                            color: .appAccent,
                            action: { showDocumentScanner = true }
                        )
                    } else {
                        actionButton(
                            title: "Scan Receipt",
                            icon: "doc.viewfinder.fill",
                            color: .appAccent,
                            action: { showDocumentScanner = true }
                        )
                    }

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
        // VisionKit Document Scanner for best quality
        .fullScreenCover(isPresented: $showDocumentScanner) {
            if #available(iOS 16.0, *), VNDocumentCameraViewController.isSupported {
                DocumentCameraView { scannedImages in
                    guard let firstImage = scannedImages.first else { return }
                    selectedImage = firstImage
                    hasProcessed = false // Reset for new scan
                    showDocumentScanner = false
                    scanReceipt()
                }
                .ignoresSafeArea()
            } else {
                // Fallback to basic camera
                CameraView { capturedImage in
                    selectedImage = capturedImage
                    hasProcessed = false // Reset for new scan
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

        // Derive the subtotal: prefer the parsed value; fall back to sum of items
        let itemsSubtotal = parsed.items.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
        let subtotal  = parsed.subtotal  ?? itemsSubtotal
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

        // Add all line items with correct unit pricing
        for item in parsed.items {
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

// MARK: - RestaurantInputView

struct RestaurantInputView: View {
    @Binding var restaurantName: String
    let parsedReceipt: ParsedReceipt?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    private var hasReceiptDetails: Bool {
        guard let receipt = parsedReceipt else { return false }
        return receipt.subtotal != nil || receipt.tax != nil || 
               receipt.tip != nil || receipt.discount != nil || receipt.total != nil
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            Form {
                restaurantSection
                
                if parsedReceipt != nil {
                    itemsSection
                    
                    if hasReceiptDetails {
                        receiptDetailsSection
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Receipt Info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.textSecondary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Continue") {
                    onSave()
                    dismiss()
                }
                .foregroundStyle(.appAccent)
                .fontWeight(.semibold)
                .disabled(restaurantName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
    
    // MARK: - Sections
    
    private var restaurantSection: some View {
        Section {
            TextField("Restaurant Name", text: $restaurantName)
                .foregroundStyle(.white)
            
            if let name = parsedReceipt?.restaurantName, !name.isEmpty {
                Text("Auto-detected from receipt")
                    .font(.caption)
                    .foregroundStyle(.appAccent)
            }
        } header: {
            Text("Restaurant")
        }
        .listRowBackground(Color.cardBackground)
    }
    
    private var itemsSection: some View {
        Section {
            if let receipt = parsedReceipt {
                if !receipt.items.isEmpty {
                    itemsDetectedContent(receipt: receipt)
                } else {
                    noItemsDetectedContent
                }
            }
        } header: {
            Text("Items")
        }
        .listRowBackground(Color.cardBackground)
    }
    
    @ViewBuilder
    private func itemsDetectedContent(receipt: ParsedReceipt) -> some View {
        itemsCountRow(count: receipt.items.count)
        itemsPreviewList(items: receipt.items)
        
        if receipt.items.count > 3 {
            moreItemsIndicator(count: receipt.items.count - 3)
        }
    }
    
    private func itemsCountRow(count: Int) -> some View {
        let countText = "\(count)"
        return HStack {
            Text("Items detected")
                .foregroundStyle(.textSecondary)
            Spacer()
            Text(countText)
                .foregroundStyle(.appAccent)
                .fontWeight(.semibold)
        }
    }
    
    @ViewBuilder
    private func itemsPreviewList(items: [ParsedLineItem]) -> some View {
        ForEach(Array(items.prefix(3)), id: \.name) { item in
            itemPreviewRow(item: item)
        }
    }
    
    private func itemPreviewRow(item: ParsedLineItem) -> some View {
        let priceText = String(format: "$%.2f", item.price)
        return HStack {
            Text(item.name)
                .font(.caption)
                .foregroundStyle(.white)
            Spacer()
            Text(priceText)
                .font(.caption)
                .foregroundStyle(.textSecondary)
        }
    }
    
    private func moreItemsIndicator(count: Int) -> some View {
        let text = "+ \(count) more items"
        return Text(text)
            .font(.caption)
            .foregroundStyle(.textSecondary)
    }
    
    private var noItemsDetectedContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.appWarning)
            Text("No items detected — you can add them manually")
                .font(.caption)
                .foregroundStyle(.appWarning)
        }
    }
    
    private var receiptDetailsSection: some View {
        Section {
            if let receipt = parsedReceipt {
                receiptDetailsContent(receipt: receipt)
            }
        } header: {
            Text("Receipt Details")
        }
        .listRowBackground(Color.cardBackground)
    }
    
    @ViewBuilder
    private func receiptDetailsContent(receipt: ParsedReceipt) -> some View {
        if let subtotal = receipt.subtotal {
            receiptRow(label: "Subtotal", amount: subtotal, color: .textSecondary)
        }
        
        if let discount = receipt.discount {
            receiptRow(label: "Discount", amount: discount, color: .green, prefix: "-")
        }
        
        if let tax = receipt.tax {
            receiptRow(label: "Tax", amount: tax, color: .textSecondary)
        }
        
        if let tip = receipt.tip {
            receiptRow(label: "Tip", amount: tip, color: .textSecondary)
        }
        
        if let total = receipt.total {
            totalRow(amount: total)
        }
    }
    
    private func totalRow(amount: Double) -> some View {
        let amountText = String(format: "$%.2f", amount)
        return HStack {
            Text("Total")
                .foregroundStyle(.white)
                .fontWeight(.semibold)
            Spacer()
            Text(amountText)
                .foregroundStyle(.appAccent)
                .fontWeight(.semibold)
        }
    }
    
    private func receiptRow(label: String, amount: Double, color: Color, prefix: String = "") -> some View {
        let amountText = prefix + String(format: "$%.2f", amount)
        return HStack {
            Text(label)
                .foregroundStyle(.white)
            Spacer()
            Text(amountText)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    NavigationStack {
        ScanView()
    }
}
