//
//  ScanView.swift
//  CheckMate
//
//  Created by Syam Shukla on 2/18/26.
//

import SwiftUI
import AVFoundation
import VisionKit

struct ScanView: View {
    /// Called after a receipt is created and saved. HomeView uses this to navigate.
    var onReceiptCreated: ((Receipt) -> Void)?

    @State private var showDocumentScanner = false
    @State private var libraryPickerPresented = false
    @State private var selectedImage: UIImage?
    @State private var isProcessing = false
    @State private var showCameraPermissionAlert = false
    @State private var parsedItems: [ParsedLineItem] = []
    @State private var showRestaurantInput = false
    @State private var restaurantName = ""
    @State private var createdReceipt: Receipt?
    @State private var showItemAssign = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 24) {
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
        // VisionKit document scanner (primary)
        .fullScreenCover(isPresented: $showDocumentScanner) {
            DocumentScannerView { scannedImage in
                selectedImage = scannedImage
                showDocumentScanner = false
                // Auto-process immediately after scan
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
                    lineItems: parsedItems,
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
            Text("CheckMate needs camera access to scan receipts.")
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
        isProcessing = true
        Task {
            let items = await OCRService.shared.extractLineItems(from: image)
            await MainActor.run {
                parsedItems = items
                isProcessing = false
                showRestaurantInput = true
            }
        }
    }

    private func createReceipt() {
        let subtotal = parsedItems.reduce(0) { $0 + $1.price }
        let receipt = Receipt(restaurantName: restaurantName, subtotal: subtotal)
        for item in parsedItems {
            receipt.lineItems.append(LineItem(name: item.name, price: item.price))
        }
        modelContext.insert(receipt)
        try? modelContext.save()
        onReceiptCreated?(receipt)
        createdReceipt = receipt
        showItemAssign = true
    }
}

// MARK: - DocumentScannerView (VisionKit)

struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: (UIImage) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: (UIImage) -> Void
        init(onScan: @escaping (UIImage) -> Void) { self.onScan = onScan }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // Use the first scanned page (receipts are typically one page)
            // VisionKit automatically applies perspective correction + edge detection
            let image = scan.imageOfPage(at: 0)
            onScan(image)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            print("Document scanner error: \(error)")
            controller.dismiss(animated: true)
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
    let lineItems: [ParsedLineItem]
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            Form {
                Section {
                    TextField("Restaurant Name", text: $restaurantName)
                        .foregroundStyle(.white)

                    if !lineItems.isEmpty {
                        HStack {
                            Text("Items found")
                                .foregroundStyle(.textSecondary)
                            Spacer()
                            Text("\(lineItems.count)")
                                .foregroundStyle(.appAccent)
                                .fontWeight(.semibold)
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
                }
                .listRowBackground(Color.cardBackground)
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
