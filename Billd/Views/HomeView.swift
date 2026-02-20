//
//  HomeView.swift
//  Billd
//
//  Created by Syam Shukla on 2/18/26.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @Environment(\.modelContext) private var modelContext

    @State private var showScanSheet = false
    @State private var selectedReceipt: Receipt?
    @State private var scannedReceipt: Receipt?
    @State private var showDeleteAllAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if receipts.isEmpty {
                    emptyState
                } else {
                    receiptList
                }
            }
            .navigationTitle("CheckMate")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !receipts.isEmpty {
                        Button(action: { showDeleteAllAlert = true }) {
                            Text("Delete All")
                                .foregroundStyle(.red)
                                .fontWeight(.medium)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showScanSheet = true }) {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                            .foregroundStyle(.appAccent)
                    }
                }
            }
            .alert("Delete All Receipts?", isPresented: $showDeleteAllAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    for receipt in receipts {
                        modelContext.delete(receipt)
                    }
                }
            } message: {
                Text("This will permanently delete all \(receipts.count) receipt\(receipts.count == 1 ? "" : "s"). This action cannot be undone.")
            }
            .sheet(isPresented: $showScanSheet, onDismiss: {
                // After sheet closes, if a receipt was just created, navigate to it
                if let receipt = scannedReceipt {
                    selectedReceipt = receipt
                    scannedReceipt = nil
                }
            }) {
                NavigationStack {
                    ScanView(onReceiptCreated: { receipt in
                        scannedReceipt = receipt
                        showScanSheet = false
                    })
                }
            }
            .navigationDestination(item: $selectedReceipt) { receipt in
                ItemAssignView(receipt: receipt)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "receipt")
                    .font(.system(size: 44))
                    .foregroundStyle(.appAccent)
            }

            VStack(spacing: 8) {
                Text("No Receipts Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("Scan a receipt to start splitting the bill")
                    .font(.subheadline)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { showScanSheet = true }) {
                HStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .fontWeight(.semibold)
                    Text("Scan Receipt")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.appAccent)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(color: Color.appAccent.opacity(0.4), radius: 12, y: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Receipt List

    var receiptList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(receipts) { receipt in
                    ReceiptCard(receipt: receipt)
                        .onTapGesture { selectedReceipt = receipt }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    modelContext.delete(receipt)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(receipt)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - ReceiptCard

struct ReceiptCard: View {
    let receipt: Receipt

    var peopleColors: [Color] {
        let people = receipt.splits.compactMap { $0.person }
        return Array(Set(people.map { $0.color })).prefix(5).map { Color(hex: $0) }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.appAccent)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(receipt.restaurantName.isEmpty ? "Untitled Receipt" : receipt.restaurantName)
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Text(receipt.date, format: Date.FormatStyle(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.textSecondary)

                    if !receipt.splits.isEmpty {
                        Text("·")
                            .foregroundStyle(.textSecondary)
                        Text("\(receipt.splits.count) people")
                            .font(.caption)
                            .foregroundStyle(.textSecondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(String(format: "$%.2f", receipt.total))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                // Person color dots
                if !peopleColors.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(Array(peopleColors.enumerated()), id: \.offset) { _, color in
                            Circle()
                                .fill(color)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color.cardBackground, lineWidth: 1.5))
                        }
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.textSecondary)
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    HomeView()
        .modelContainer(for: Receipt.self, inMemory: true)
}
