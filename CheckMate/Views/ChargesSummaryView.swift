//
//  ChargesSummaryView.swift
//  CheckMate
//
//  Screen 2 of 2: Edit tax / tip / discount and review the final per-person split.
//

import SwiftUI
import SwiftData

struct ChargesSummaryView: View {
    @Bindable var receipt: Receipt
    let splitPeople: [Person]
    /// Notifies the parent (ItemAssignView) that the split was saved.
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var splits: [ObjectIdentifier: SplitDetails] = [:]

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    chargesCard
                    splitCardsSection
                    saveButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Charges & Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { recalculate() }
        .onChange(of: receipt.tax)      { _, _ in recalculate() }
        .onChange(of: receipt.tip)      { _, _ in recalculate() }
        .onChange(of: receipt.discount) { _, _ in recalculate() }
    }

    // MARK: - Charges Card

    var chargesCard: some View {
        VStack(spacing: 0) {
            sectionHeader("CHARGES", icon: "doc.text.fill")
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                chargeRow(label: "Subtotal", value: String(format: "$%.2f", receipt.subtotal), editable: false)
                Divider().background(Color.elevatedCard)
                chargeFieldRow(label: "Tax", value: $receipt.tax)
                Divider().background(Color.elevatedCard)
                chargeFieldRow(label: "Tip", value: $receipt.tip)
                Divider().background(Color.elevatedCard)
                chargeFieldRow(label: "Discount (–)", value: $receipt.discount)
                Divider().background(Color.elevatedCard)

                HStack {
                    Text("Total")
                        .foregroundStyle(.white)
                        .fontWeight(.bold)
                    Spacer()
                    Text(String(format: "$%.2f", max(0, receipt.subtotal + receipt.tax + receipt.tip - receipt.discount)))
                        .foregroundStyle(.appAccent)
                        .fontWeight(.bold)
                        .font(.title3)
                }
                .padding(14)
            }
            .background(Color.elevatedCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Per-Person Cards

    @ViewBuilder
    var splitCardsSection: some View {
        if !splitPeople.isEmpty {
            VStack(spacing: 10) {
                sectionHeader("EACH PERSON OWES", icon: "person.2.fill")

                ForEach(splitPeople.sorted { $0.name < $1.name }) { person in
                    let key = ObjectIdentifier(person)
                    let detail = splits[key] ?? SplitDetails(subtotal: 0, tax: 0, tip: 0, discount: 0, total: 0)
                    PersonSplitCard(person: person, detail: detail)
                }
            }
        }
    }

    // MARK: - Save Button

    var saveButton: some View {
        Button(action: saveSplit) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Save Split")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color.appAccent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.top, 4)
    }

    // MARK: - Row Helpers

    private func chargeRow(label: String, value: String, editable: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(editable ? .white : .textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(.textSecondary)
        }
        .padding(14)
    }

    private func chargeFieldRow(label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white)
            Spacer()
            HStack(spacing: 2) {
                Text("$")
                    .foregroundStyle(.textSecondary)
                TextField("0.00", value: value, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 90)
            }
        }
        .padding(14)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Logic

    private func recalculate() {
        receipt.subtotal = receipt.lineItems.reduce(0) { $0 + $1.totalPrice }
        receipt.updateTotal()
        let raw = SplitCalculatorService.shared.calculateSplit(
            lineItems: receipt.lineItems,
            people: splitPeople,
            taxAmount: receipt.tax,
            tipAmount: receipt.tip,
            discountAmount: receipt.discount
        )
        // Re-key by ObjectIdentifier so we can look up by person in the view
        splits = Dictionary(uniqueKeysWithValues: raw.map { (ObjectIdentifier($0.key), $0.value) })
    }

    private func saveSplit() {
        // Remove any previously saved splits for this receipt
        for split in receipt.splits {
            modelContext.delete(split)
        }
        receipt.splits.removeAll()

        // Insert fresh splits
        for person in splitPeople {
            let key = ObjectIdentifier(person)
            let detail = splits[key] ?? SplitDetails(subtotal: 0, tax: 0, tip: 0, discount: 0, total: 0)
            let split = Split(
                receipt: receipt,
                person: person,
                amountOwed: detail.total,
                itemsSubtotal: detail.subtotal,
                taxAmount: detail.tax,
                tipAmount: detail.tip,
                discountAmount: detail.discount
            )
            modelContext.insert(split)
            receipt.splits.append(split)
        }

        receipt.updateTotal()
        try? modelContext.save()
        onSaved()
        dismiss()
    }
}

// MARK: - PersonSplitCard

struct PersonSplitCard: View {
    let person: Person
    let detail: SplitDetails

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: person.color).opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(Color(hex: person.color), lineWidth: 1.5)
                    )
                    .overlay(Text(person.emoji).font(.title3))

                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                    Text("Total owed")
                        .font(.caption)
                        .foregroundStyle(.textSecondary)
                }

                Spacer()

                Text(String(format: "$%.2f", detail.total))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(hex: person.color))
            }
            .padding(16)

            Divider().background(Color.elevatedCard)

            // Breakdown rows
            VStack(spacing: 0) {
                breakdownRow(label: "Items", value: detail.subtotal)
                if detail.tax > 0.005 {
                    Divider().background(Color.elevatedCard).padding(.horizontal, 14)
                    breakdownRow(label: "Tax", value: detail.tax)
                }
                if detail.tip > 0.005 {
                    Divider().background(Color.elevatedCard).padding(.horizontal, 14)
                    breakdownRow(label: "Tip", value: detail.tip)
                }
                if detail.discount > 0.005 {
                    Divider().background(Color.elevatedCard).padding(.horizontal, 14)
                    breakdownRow(label: "Discount", value: -detail.discount, isNegative: true)
                }
            }
            .padding(.bottom, 8)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: person.color).opacity(0.25), lineWidth: 1)
        )
    }

    private func breakdownRow(label: String, value: Double, isNegative: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.textSecondary)
            Spacer()
            Text(String(format: "%@$%.2f", isNegative ? "−" : "+", abs(value)))
                .font(.subheadline)
                .foregroundStyle(isNegative ? .appDestructive : .textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
