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
            // Tap anywhere on the background to dismiss the numpad
            Color.appBackground.ignoresSafeArea()
                .onTapGesture { hideKeyboard() }

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
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button("Done") { hideKeyboard() }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onAppear { recalculate() }
        .onChange(of: receipt.tax)      { _, _ in recalculate() }
        .onChange(of: receipt.tip)      { _, _ in recalculate() }
        .onChange(of: receipt.discount) { _, _ in recalculate() }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
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
                    PersonSplitCard(
                        person: person,
                        detail: detail,
                        receipt: receipt,
                        restaurantName: receipt.restaurantName
                    )
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
    let receipt: Receipt
    let restaurantName: String
    @State private var isExpanded = false

    /// Items this person has a share in, with their computed amount.
    private var assignedItems: [(LineItem, Double)] {
        receipt.lineItems.compactMap { item in
            let amount = item.amountOwed(byPersonID: person.personID)
            guard amount > 0.005 else { return nil }
            return (item, amount)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header (tappable to expand/collapse) ──
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: person.color).opacity(0.25))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(Color(hex: person.color), lineWidth: 1.5))
                        .overlay(Text(person.emoji).font(.title3))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .foregroundStyle(.white).fontWeight(.semibold)
                        Text("\(assignedItems.count) item\(assignedItems.count == 1 ? "" : "s") · tap to see breakdown")
                            .font(.caption).foregroundStyle(.textSecondary)
                    }

                    Spacer()

                    Text(String(format: "$%.2f", detail.total))
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(Color(hex: person.color))

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.textSecondary)
                        .frame(width: 16)
                }
                .padding(16)
            }
            .buttonStyle(PlainButtonStyle())

            // ── Collapsible item breakdown ──
            if isExpanded && !assignedItems.isEmpty {
                Divider().background(Color.elevatedCard)

                VStack(spacing: 0) {
                    ForEach(Array(assignedItems.enumerated()), id: \.offset) { idx, pair in
                        let (item, amount) = pair
                        HStack(spacing: 10) {
                            // Portion badge for multi-qty items
                            if item.quantity > 1, let portions = item.portionMap[person.personID], portions > 0 {
                                Text("\(portions)×")
                                    .font(.caption2).fontWeight(.bold)
                                    .foregroundStyle(Color(hex: person.color))
                                    .frame(width: 22)
                            } else {
                                Circle()
                                    .fill(Color(hex: person.color).opacity(0.5))
                                    .frame(width: 6, height: 6)
                                    .frame(width: 22)
                            }
                            Text(item.name.isEmpty ? "Item" : item.name)
                                .font(.subheadline).foregroundStyle(.white)
                            Spacer()
                            Text(String(format: "$%.2f", amount))
                                .font(.subheadline).foregroundStyle(.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            idx % 2 == 0
                                ? Color.clear
                                : Color.white.opacity(0.02)
                        )
                        if idx < assignedItems.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.05))
                                .padding(.leading, 48)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── Charges breakdown (items subtotal + tax/tip/discount) ──
            Divider().background(Color.elevatedCard)

            VStack(spacing: 0) {
                breakdownRow(label: isExpanded ? "Items subtotal" : "Items", value: detail.subtotal)
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

            // ── Venmo request button ──
            Divider().background(Color.elevatedCard)
            venmoButton
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: person.color).opacity(isExpanded ? 0.45 : 0.2), lineWidth: 1)
        )
    }

    // MARK: Venmo — opens app with amount pre-filled; user picks recipient inside Venmo

    private var venmoButton: some View {
        Button {
            openVenmo(amount: detail.total)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 15))
                Text("Request \(String(format: "$%.2f", detail.total)) on Venmo")
                    .fontWeight(.semibold)
                    .font(.subheadline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(hex: "0074DE"))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func openVenmo(amount: Double) {
        let note = "Billd: \(restaurantName.isEmpty ? "dinner" : restaurantName)"
        let amountStr = String(format: "%.2f", amount)
        // .urlQueryAllowed keeps + unencoded, so Venmo shows literal '+' characters in the
        // note field (common OCR artifacts from receipt borders like +----+). Remove + and
        // other structural characters (&, =, #) so they get percent-escaped instead.
        var valueEncoding = CharacterSet.urlQueryAllowed
        valueEncoding.remove(charactersIn: "+&=#")
        guard let encoded = note.addingPercentEncoding(withAllowedCharacters: valueEncoding) else { return }

        // No recipient pre-filled — user selects inside Venmo so it links to the correct account
        let appURL = URL(string: "venmo://paycharge?txn=charge&amount=\(amountStr)&note=\(encoded)")
        let webURL = URL(string: "https://venmo.com/?txn=charge&amount=\(amountStr)&note=\(encoded)")

        if let appURL, UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL {
            UIApplication.shared.open(webURL)
        }
    }

    private func breakdownRow(label: String, value: Double, isNegative: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline).foregroundStyle(.textSecondary)
            Spacer()
            Text(String(format: "%@$%.2f", isNegative ? "−" : "+", abs(value)))
                .font(.subheadline)
                .foregroundStyle(isNegative ? .appDestructive : .textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
