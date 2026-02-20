//
//  ScanView.swift
//  Billd
//
//  Created by Syam Shukla on 2/18/26.
//

import SwiftUI
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
    @State private var hasProcessed = false  // Prevent double-processing
    @State private var showCameraPermissionAlert = false
    @State private var parsedReceipt: ParsedReceipt?
    @State private var showRestaurantInput = false
    @State private var restaurantName = ""
    @State private var createdReceipt: Receipt?
    @State private var showItemAssign = false
    
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
        // Simple camera capture (one shot)
        .fullScreenCover(isPresented: $showDocumentScanner) {
            CameraView { capturedImage in
                // Only process if we haven't already
                guard !hasProcessed else { return }
                selectedImage = capturedImage
                showDocumentScanner = false
                // Process immediately
                scanReceipt()
            }
            .ignoresSafeArea()
        }
        // Photo library fallback
        .sheet(isPresented: $libraryPickerPresented) {
            ImagePicker(image: $selectedImage, sourceType: .photoLibrary)
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
        guard let image = selectedImage, !hasProcessed else { return }
        hasProcessed = true
        isProcessing = true
        Task {
            let receipt = await OCRService.shared.extractReceiptData(from: image)
            await MainActor.run {
                parsedReceipt = receipt
                // Pre-fill restaurant name if available
                restaurantName = receipt.restaurantName ?? ""
                isProcessing = false
                showRestaurantInput = true
            }
        }
    }

    private func createReceipt() {
        guard let parsed = parsedReceipt else { return }
        
        // Use parsed total if available, otherwise calculate from items
        let finalTotal = parsed.total ?? parsed.items.reduce(0) { $0 + $1.price }
        
        let receipt = Receipt(restaurantName: restaurantName, subtotal: finalTotal)
        
        // Add all line items
        for item in parsed.items {
            receipt.lineItems.append(LineItem(name: item.name, price: item.price))
        }
        
        // Store tax, tip, discount info in the receipt if available
        // Note: You may want to add these properties to your Receipt model
        // For now, we'll just use the subtotal which represents the actual total
        
        modelContext.insert(receipt)
        try? modelContext.save()
        onReceiptCreated?(receipt)
        createdReceipt = receipt
        showItemAssign = true
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

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            Form {
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
                
                if let receipt = parsedReceipt {
                    Section {
                        if !receipt.items.isEmpty {
                            HStack {
                                Text("Items detected")
                                    .foregroundStyle(.textSecondary)
                                Spacer()
                                Text("\(receipt.items.count)")
                                    .foregroundStyle(.appAccent)
                                    .fontWeight(.semibold)
                            }
                            
                            // Show first few items as preview
                            ForEach(receipt.items.prefix(3), id: \.name) { item in
                                HStack {
                                    Text(item.name)
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("$\(item.price, specifier: "%.2f")")
                                        .font(.caption)
                                        .foregroundStyle(.textSecondary)
                                }
                            }
                            
                            if receipt.items.count > 3 {
                                Text("+ \(receipt.items.count - 3) more items")
                                    .font(.caption)
                                    .foregroundStyle(.textSecondary)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.appWarning)
                                Text("No items detected — you can add them manually")
                                    .font(.caption)
                                    .foregroundStyle(.appWarning)
                            }
                        }
                    } header: {
                        Text("Items")
                    }
                    .listRowBackground(Color.cardBackground)
                    
                    // Show totals if available
                    if receipt.subtotal != nil || receipt.tax != nil || receipt.tip != nil || receipt.discount != nil || receipt.total != nil {
                        Section {
                            if let subtotal = receipt.subtotal {
                                HStack {
                                    Text("Subtotal")
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("$\(subtotal, specifier: "%.2f")")
                                        .foregroundStyle(.textSecondary)
                                }
                            }
                            
                            if let discount = receipt.discount {
                                HStack {
                                    Text("Discount")
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("-$\(discount, specifier: "%.2f")")
                                        .foregroundStyle(.green)
                                }
                            }
                            
                            if let tax = receipt.tax {
                                HStack {
                                    Text("Tax")
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("$\(tax, specifier: "%.2f")")
                                        .foregroundStyle(.textSecondary)
                                }
                            }
                            
                            if let tip = receipt.tip {
                                HStack {
                                    Text("Tip")
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("$\(tip, specifier: "%.2f")")
                                        .foregroundStyle(.textSecondary)
                                }
                            }
                            
                            if let total = receipt.total {
                                HStack {
                                    Text("Total")
                                        .foregroundStyle(.white)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("$\(total, specifier: "%.2f")")
                                        .foregroundStyle(.appAccent)
                                        .fontWeight(.semibold)
                                }
                            }
                        } header: {
                            Text("Receipt Details")
                        }
                        .listRowBackground(Color.cardBackground)
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
}

#Preview {
    NavigationStack {
        ScanView()
    }
}
