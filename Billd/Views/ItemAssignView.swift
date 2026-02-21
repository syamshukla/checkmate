//
//  ItemAssignView.swift
//  Billd
//
//  Screen 1 of 2: Assign items to people and split individual items.
//

import SwiftUI
import SwiftData

// MARK: - Main View

struct ItemAssignView: View {
    @Bindable var receipt: Receipt
    /// Called after the split is saved — used by ScanView to close its sheet.
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Current user preference
    @AppStorage("currentUserID") private var currentUserID: String = ""
    @Query private var allPeople: [Person]
    
    // People added to THIS split session
    @State private var splitPeople: [Person] = []
    // The currently "active" person — tapping items assigns to them
    @State private var activePerson: Person?
    // Even-split toggle
    @State private var evenSplit = false

    // Sheet / navigation state
    @State private var showPeoplePicker = false
    @State private var itemForSplitSheet: LineItem?
    @State private var showAddItem = false
    @State private var showCharges = false
    @State private var savedFromCharges = false
    
    // Computed: find current user
    var currentUser: Person? {
        allPeople.first { $0.personID == currentUserID }
    }
    
    var isCurrentUserInSplit: Bool {
        guard let currentUser = currentUser else { return false }
        return splitPeople.contains { $0.persistentModelID == currentUser.persistentModelID }
    }

    // MARK: Computed

    var allAssigned: Bool {
        !receipt.lineItems.isEmpty &&
        receipt.lineItems.allSatisfy { !$0.assignedPeople.isEmpty }
    }

    var canProceed: Bool { !splitPeople.isEmpty && allAssigned }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 14) {
                        if !splitPeople.isEmpty {
                            evenSplitRow
                        }
                        itemsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, splitPeople.isEmpty ? 150 : 220)
                }
            }

            combinedBottomBar
        }
        .navigationTitle(receipt.restaurantName.isEmpty ? "Assign Items" : receipt.restaurantName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showPeoplePicker) {
            PeoplePickerView(splitPeople: $splitPeople)
        }
        .sheet(item: $itemForSplitSheet) { item in
            ItemSplitSheet(item: item, splitPeople: splitPeople)
        }
        .sheet(isPresented: $showAddItem, onDismiss: {
            // Remove blank item if user cancelled
            if let last = receipt.lineItems.last, last.name.trimmingCharacters(in: .whitespaces).isEmpty {
                receipt.lineItems.removeLast()
                receipt.subtotal = receipt.lineItems.reduce(0) { $0 + $1.totalPrice }
            }
        }) {
            if let last = receipt.lineItems.last {
                AddItemSheet(item: last) { _ in
                    receipt.subtotal = receipt.lineItems.reduce(0) { $0 + $1.totalPrice }
                    showAddItem = false
                }
            }
        }
        .navigationDestination(isPresented: $showCharges) {
            ChargesSummaryView(receipt: receipt, splitPeople: splitPeople, onSaved: {
                savedFromCharges = true
            })
        }
        .onChange(of: showCharges) { _, isShowing in
            if !isShowing && savedFromCharges {
                onDone()
                dismiss()
            }
        }
        .onAppear { restorePeople() }
    }

    // MARK: - Combined Bottom Bar

    /// Single bottom bar that handles both people management and item assignment.
    /// Replaces the old split between peopleManagementSection (scroll) and personSelectorFooter (overlay).
    /// Background is fully opaque to prevent content bleed-through.
    var combinedBottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            if splitPeople.isEmpty {
                // ── Empty state: prompt to add people ──
                Button(action: { showPeoplePicker = true }) {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(.appAccent)

                        if currentUser != nil {
                            Text("You're automatically included!")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Add others who shared this bill")
                                .font(.subheadline)
                                .foregroundStyle(.textSecondary)
                        } else {
                            Text("Add people to start splitting")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Tap to select who's on this bill")
                                .font(.subheadline)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                // ── Person chips + inline add chip ──
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(splitPeople) { person in
                            PersonSelectorChip(
                                person: person,
                                isActive: activePerson?.persistentModelID == person.persistentModelID,
                                subtotal: subtotalString(for: person)
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    toggleActive(person)
                                }
                            }
                            .onLongPressGesture { removePerson(person) }
                        }

                        // Add Me chip (only when current user not present)
                        if let currentUser = currentUser, !isCurrentUserInSplit {
                            Button(action: { addCurrentUser() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.fill.checkmark")
                                        .font(.caption)
                                    Text("Add Me")
                                        .font(.caption).fontWeight(.semibold)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.appAccent.opacity(0.85))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                }

                // ── Full-width Add Person button ──
                Button(action: { showPeoplePicker = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Add Person")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(Color.appAccent)
                    .background(Color.appAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.appAccent.opacity(0.35), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

                // ── Continue button (slides in when all items assigned) ──
                if canProceed {
                    Button(action: { showCharges = true }) {
                        HStack(spacing: 8) {
                            Text("Continue")
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.appAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color.appBackground)  // Fully opaque — no content bleed-through
    }

    // MARK: - Even Split Toggle

    var evenSplitRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Split Evenly")
                    .foregroundStyle(.white)
                    .fontWeight(.medium)
                Text("Divide every item equally among all people")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $evenSplit)
                .tint(.appAccent)
                .labelsHidden()
                .onChange(of: evenSplit) { _, on in
                    if on {
                        activePerson = nil
                        for item in receipt.lineItems {
                            item.assignedPeople = splitPeople
                        }
                    } else {
                        // FIX: When toggled off, clear all assignments
                        for item in receipt.lineItems {
                            item.assignedPeople.removeAll()
                        }
                    }
                }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
        }
    }

    // MARK: - Items Section

    var itemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Minimal header
            HStack {
                Text("Items")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Spacer()
                
                // Unassigned count (only if people exist)
                if !splitPeople.isEmpty {
                    let unassigned = receipt.lineItems.filter { $0.assignedPeople.isEmpty }.count
                    if unassigned > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.appWarning)
                                .frame(width: 6, height: 6)
                            Text("\(unassigned)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.appWarning)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.appWarning.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }

            // Items list
            VStack(spacing: 6) {
                ForEach(receipt.lineItems) { item in
                    ItemRow(
                        item: item,
                        splitPeople: splitPeople,
                        activePerson: activePerson
                    ) {
                        handleItemTap(item)
                    }
                    .contextMenu {
                        Button {
                            itemForSplitSheet = item
                        } label: {
                            Label("Split by Weight", systemImage: "chart.pie.fill")
                        }
                        // Quick-assign everyone
                        Button {
                            item.assignedPeople = splitPeople
                            item.portionMap = [:]
                        } label: {
                            Label("Assign to Everyone", systemImage: "person.3.fill")
                        }
                        // Clear
                        if !item.assignedPeople.isEmpty {
                            Button(role: .destructive) {
                                item.assignedPeople.removeAll()
                                item.portionMap = [:]
                            } label: {
                                Label("Clear Assignment", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    receipt.lineItems.remove(atOffsets: offsets)
                    receipt.subtotal = receipt.lineItems.reduce(0) { $0 + $1.totalPrice }
                }
            }

            // Add item button (minimal)
            Button(action: {
                let newItem = LineItem(name: "", price: 0)
                receipt.lineItems.append(newItem)
                showAddItem = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                    Text("Add Item")
                        .fontWeight(.medium)
                }
                .foregroundStyle(.appAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
        }
    }

    // MARK: - Helpers

    private func toggleActive(_ person: Person) {
        withAnimation(.spring(duration: 0.2)) {
            if activePerson?.persistentModelID == person.persistentModelID {
                activePerson = nil
            } else {
                activePerson = person
                evenSplit = false
            }
        }
    }

    private func removePerson(_ person: Person) {
        withAnimation {
            splitPeople.removeAll { $0.persistentModelID == person.persistentModelID }
            if activePerson?.persistentModelID == person.persistentModelID {
                activePerson = nil
            }
            for item in receipt.lineItems {
                item.assignedPeople.removeAll { $0.persistentModelID == person.persistentModelID }
            }
            evenSplit = false
        }
    }

    private func handleItemTap(_ item: LineItem) {
        // Always require an active person - no modal
        guard let active = activePerson else { return }
        
        evenSplit = false
        let alreadyAssigned = item.assignedPeople.contains {
            $0.persistentModelID == active.persistentModelID
        }
        if alreadyAssigned {
            item.assignedPeople.removeAll { $0.persistentModelID == active.persistentModelID }
        } else {
            item.assignedPeople.append(active)
        }
    }

    private func subtotalString(for person: Person) -> String {
        let total = receipt.lineItems.reduce(0.0) { $0 + $1.amountOwed(byPersonID: person.personID) }
        return String(format: "$%.2f", total)
    }

    private func restorePeople() {
        guard splitPeople.isEmpty else { return }
        // Restore from saved splits first
        let fromSplits = receipt.splits.compactMap { $0.person }
        if !fromSplits.isEmpty {
            splitPeople = fromSplits
            return
        }
        // Fall back to people visible in item assignments
        var seen = Set<PersistentIdentifier>()
        var restored: [Person] = []
        for item in receipt.lineItems {
            for person in item.assignedPeople {
                if seen.insert(person.persistentModelID).inserted {
                    restored.append(person)
                }
            }
        }
        splitPeople = restored
        
        // Auto-add current user if this is a fresh split
        if splitPeople.isEmpty, let currentUser = currentUser {
            splitPeople.append(currentUser)
        }
    }
    
    private func addCurrentUser() {
        guard let currentUser = currentUser else { return }
        withAnimation {
            if !splitPeople.contains(where: { $0.persistentModelID == currentUser.persistentModelID }) {
                splitPeople.append(currentUser)
                // Optionally make them the active person
                activePerson = currentUser
            }
        }
    }
}

// MARK: - PersonSelectorChip (Bottom Bar)

/// Compact horizontal pill: emoji + name + running subtotal.
/// Much shorter than the old 60px-circle design so the bottom bar doesn't eat screen.
struct PersonSelectorChip: View {
    let person: Person
    let isActive: Bool
    let subtotal: String

    var body: some View {
        HStack(spacing: 10) {
            // Compact avatar
            ZStack {
                Circle()
                    .fill(isActive
                          ? Color(hex: person.color)
                          : Color(hex: person.color).opacity(0.35))
                    .frame(width: 36, height: 36)
                Text(person.emoji)
                    .font(.system(size: 17))
            }

            // Name + running total
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .medium)
                    .foregroundStyle(isActive ? .white : .textSecondary)
                    .lineLimit(1)
                Text(subtotal)
                    .font(.caption2)
                    .foregroundStyle(isActive
                                     ? Color(hex: person.color)
                                     : .textSecondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isActive ? Color(hex: person.color).opacity(0.2) : Color.elevatedCard)
        )
        .overlay(
            Capsule()
                .stroke(isActive ? Color(hex: person.color).opacity(0.7) : Color.clear,
                        lineWidth: 1.5)
        )
        .scaleEffect(isActive ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

// MARK: - PersonChip (unused, but keeping for compatibility)

struct PersonChip: View {
    let person: Person
    let isActive: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color(hex: person.color).opacity(isActive ? 1 : 0.4))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(Color(hex: person.color), lineWidth: isActive ? 3 : 0)
                    )
                    .shadow(color: isActive ? Color(hex: person.color).opacity(0.6) : .clear, radius: 12, y: 4)
                Text(person.emoji)
                    .font(.system(size: 28))
            }
            .scaleEffect(isActive ? 1.05 : 1.0)
            
            Text(person.name)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? .white : .textSecondary)
                .lineLimit(1)
        }
        .frame(width: 72)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

// MARK: - ItemRow

struct ItemRow: View {
    @Bindable var item: LineItem
    let splitPeople: [Person]
    let activePerson: Person?
    let onTap: () -> Void

    var isAssignedToActive: Bool {
        guard let active = activePerson else { return false }
        return item.assignedPeople.contains { $0.persistentModelID == active.persistentModelID }
    }

    var isEveryoneAssigned: Bool {
        guard !splitPeople.isEmpty else { return false }
        let assignedIDs = Set(item.assignedPeople.map { $0.persistentModelID })
        let splitIDs    = Set(splitPeople.map { $0.persistentModelID })
        return splitIDs.isSubset(of: assignedIDs)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? "Unnamed Item" : item.name)
                        .foregroundStyle(.white)
                        .fontWeight(.medium)
                        .font(.subheadline)
                    if item.quantity > 1 {
                        HStack(spacing: 4) {
                            Text("\(item.quantity) × \(String(format: "$%.2f", item.price))")
                                .font(.caption2)
                                .foregroundStyle(.textSecondary)
                            if !item.portionMap.isEmpty {
                                let claimed = item.portionMap.values.reduce(0, +)
                                Text("· \(claimed)/\(item.quantity) portions")
                                    .font(.caption2)
                                    .foregroundStyle(.appAccent)
                            } else if !splitPeople.isEmpty {
                                Text("· hold to weight")
                                    .font(.caption2)
                                    .foregroundStyle(.textSecondary.opacity(0.5))
                            }
                        }
                    } else if !item.portionMap.isEmpty {
                        // Single item with a custom weight split — show the ratio
                        let parts = item.assignedPeople.compactMap { p -> String? in
                            let w = item.portionMap[p.personID] ?? 0
                            return w > 0 ? "\(w)" : nil
                        }
                        if !parts.isEmpty {
                            Text("weighted \(parts.joined(separator: ":"))")
                                .font(.caption2)
                                .foregroundStyle(.appAccent)
                        }
                    } else if !splitPeople.isEmpty && !item.assignedPeople.isEmpty {
                        Text("· hold to weight")
                            .font(.caption2)
                            .foregroundStyle(.textSecondary.opacity(0.5))
                    }
                }

                Spacer()

                Text(String(format: "$%.2f", item.totalPrice))
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
                    .font(.callout)

                assignmentIndicator
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                if let active = activePerson, isAssignedToActive {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: active.color).opacity(0.30),
                                    Color(hex: active.color).opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isAssignedToActive
                            ? (activePerson.map { Color(hex: $0.color).opacity(0.75) } ?? .clear)
                            : Color.white.opacity(0.07),
                        lineWidth: isAssignedToActive ? 1.5 : 0.5
                    )
            }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: item.assignedPeople.map { $0.persistentModelID })
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: activePerson?.persistentModelID)
    }

    @ViewBuilder
    var assignmentIndicator: some View {
        if splitPeople.isEmpty {
            EmptyView()
        } else if item.assignedPeople.isEmpty {
            Circle()
                .strokeBorder(Color.textSecondary.opacity(0.4), lineWidth: 1.5)
                .frame(width: 24, height: 24)
        } else if isEveryoneAssigned {
            ZStack {
                Circle()
                    .fill(Color.appAccent)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        } else {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 24, height: 24)
                ForEach(Array(item.assignedPeople.prefix(1)), id: \.persistentModelID) { person in
                    Text(person.emoji)
                        .font(.system(size: 12))
                }
            }
        }
    }
}

// MARK: - ItemSplitSheet

struct ItemSplitSheet: View {
    @Bindable var item: LineItem
    let splitPeople: [Person]
    @Environment(\.dismiss) private var dismiss

    private var totalClaimed: Int { item.portionMap.values.reduce(0, +) }
    // Always use the weighted stepper UI — works for units (qty>1) and ratio weights (qty==1)
    private var isMultiQty: Bool { item.quantity > 1 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        itemSummaryCard
                        portionSection
                        Spacer(minLength: 20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Who gets this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.appAccent)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Item summary

    private var itemSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name.isEmpty ? "Item" : item.name)
                    .foregroundStyle(.white).fontWeight(.semibold).font(.title3)
                if item.quantity > 1 {
                    Text("\(item.quantity) × \(String(format: "$%.2f", item.price))")
                        .font(.caption).foregroundStyle(.textSecondary)
                }
            }
            Spacer()
            Text(String(format: "$%.2f", item.totalPrice))
                .foregroundStyle(.white).fontWeight(.semibold).font(.title3)
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Weighted stepper — works for units (qty>1) and ratio weights (qty==1)

    private var portionSection: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text(isMultiQty ? "How many did each person have?" : "Set the split weight for each person")
                    .font(.subheadline).foregroundStyle(.white).fontWeight(.medium)
                Spacer()
                if isMultiQty {
                    let remaining = item.quantity - totalClaimed
                    Text(remaining == 0 ? "All assigned" : "\(remaining) remaining")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(remaining == 0 ? Color.green : .appWarning)
                } else if totalClaimed > 0 {
                    // Show the ratio, e.g. "2 : 1"
                    let parts = splitPeople.compactMap { p -> String? in
                        let w = item.portionMap[p.personID] ?? 0
                        return w > 0 ? "\(w)" : nil
                    }
                    Text(parts.joined(separator: " : "))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.appAccent)
                }
            }

            // Per-person stepper rows
            VStack(spacing: 10) {
                ForEach(splitPeople) { person in
                    portionRow(for: person)
                }
            }

            // Quick actions
            HStack(spacing: 10) {
                // Split evenly (clears portionMap → equal split)
                Button {
                    var map = item.portionMap
                    map = [:]
                    item.portionMap = map
                    item.assignedPeople = splitPeople
                } label: {
                    Label("Split Evenly", systemImage: "equal.circle")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.appAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Reset all
                if !item.portionMap.isEmpty || !item.assignedPeople.isEmpty {
                    Button {
                        item.portionMap = [:]
                        item.assignedPeople = []
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.appDestructive)
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color.appDestructive.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func portionRow(for person: Person) -> some View {
        let portions = item.portionMap[person.personID] ?? 0
        // For multi-qty: cost = price per unit × units. For single-item: proportional by weight.
        let cost: Double = isMultiQty
            ? item.price * Double(portions)
            : (totalClaimed > 0 ? item.totalPrice * Double(portions) / Double(totalClaimed) : 0)

        return HStack(spacing: 14) {
            Circle()
                .fill(Color(hex: person.color))
                .frame(width: 38, height: 38)
                .overlay(Text(person.emoji).font(.system(size: 18)))

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .foregroundStyle(portions > 0 ? .white : .textSecondary)
                    .fontWeight(.medium)
                if portions > 0 {
                    Text(String(format: "$%.2f", cost))
                        .font(.caption).foregroundStyle(.textSecondary)
                }
            }

            Spacer()

            // −  N  + stepper
            HStack(spacing: 0) {
                Button { decrementPortion(person) } label: {
                    Image(systemName: "minus")
                        .frame(width: 34, height: 34)
                        .background(Color.elevatedCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(portions == 0)

                Text("\(portions)")
                    .frame(width: 34)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)

                Button { incrementPortion(person) } label: {
                    Image(systemName: "plus")
                        .frame(width: 34, height: 34)
                        .background(Color.elevatedCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                // For multi-qty, cap at total units. For single items, no cap (it's a ratio weight).
                .disabled(isMultiQty && totalClaimed >= item.quantity)
            }
            .foregroundStyle(.white)
            .font(.system(size: 14, weight: .semibold))
        }
        .padding(14)
        .background(portions > 0 ? Color(hex: person.color).opacity(0.15) : Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(portions > 0 ? Color(hex: person.color).opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: portions)
    }

    // MARK: Equal split mode (qty == 1) — simple toggles

    private var equalSplitSection: some View {
        VStack(spacing: 10) {
            // Per-person cost info
            if !item.assignedPeople.isEmpty {
                let perPerson = item.totalPrice / Double(item.assignedPeople.count)
                Text(String(format: "$%.2f each", perPerson))
                    .font(.headline).foregroundStyle(.appAccent)
                    .frame(maxWidth: .infinity).padding(12)
                    .background(Color.appAccent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Everyone button
            if !splitPeople.isEmpty {
                Button {
                    item.assignedPeople = splitPeople
                } label: {
                    HStack {
                        Image(systemName: "person.3.fill")
                        Text("Everyone").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding(14)
                    .background(Color.appAccent).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            // Per-person toggles
            ForEach(splitPeople) { person in
                let assigned = item.assignedPeople.contains { $0.persistentModelID == person.persistentModelID }
                Button {
                    if assigned {
                        item.assignedPeople.removeAll { $0.persistentModelID == person.persistentModelID }
                    } else {
                        item.assignedPeople.append(person)
                    }
                } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color(hex: person.color))
                            .frame(width: 38, height: 38)
                            .overlay(Text(person.emoji).font(.system(size: 18)))
                        Text(person.name)
                            .foregroundStyle(.white).fontWeight(.medium)
                        Spacer()
                        Image(systemName: assigned ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(assigned ? Color(hex: person.color) : .textSecondary)
                            .font(.system(size: 22))
                    }
                    .padding(14)
                    .background(assigned ? Color(hex: person.color).opacity(0.15) : Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(assigned ? Color(hex: person.color).opacity(0.5) : .clear, lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: Portion helpers

    private func incrementPortion(_ person: Person) {
        // For multi-qty items, cap at the number of units. Single items have no cap (ratio weights).
        if isMultiQty { guard totalClaimed < item.quantity else { return } }
        var map = item.portionMap
        map[person.personID] = (map[person.personID] ?? 0) + 1
        item.portionMap = map
        // Auto-assign the person if not already in the list
        if !item.assignedPeople.contains(where: { $0.personID == person.personID }) {
            item.assignedPeople.append(person)
        }
    }

    private func decrementPortion(_ person: Person) {
        var map = item.portionMap
        let current = map[person.personID] ?? 0
        if current <= 1 {
            map.removeValue(forKey: person.personID)
            item.assignedPeople.removeAll { $0.personID == person.personID }
        } else {
            map[person.personID] = current - 1
        }
        item.portionMap = map
    }
}

// MARK: - PeoplePickerView

struct PeoplePickerView: View {
    @Binding var splitPeople: [Person]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.name) private var allPeople: [Person]
    @State private var searchText = ""
    @State private var showNewPerson = false
    @AppStorage("currentUserID") private var currentUserID: String = ""

    var filtered: [Person] {
        searchText.isEmpty ? allPeople
            : allPeople.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var currentUser: Person? {
        allPeople.first { $0.personID == currentUserID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                List {
                    Section {
                        Button(action: { showNewPerson = true }) {
                            HStack(spacing: 14) {
                                Circle()
                                    .fill(Color.appAccent)
                                    .frame(width: 38, height: 38)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .foregroundStyle(.white)
                                            .fontWeight(.bold)
                                    )
                                Text("New Person")
                                    .foregroundStyle(.appAccent)
                                    .fontWeight(.medium)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    if !filtered.isEmpty {
                        Section("PAST PEOPLE") {
                            ForEach(filtered) { person in
                                Button(action: { toggle(person) }) {
                                    HStack(spacing: 14) {
                                        Circle()
                                            .fill(Color(hex: person.color))
                                            .frame(width: 38, height: 38)
                                            .overlay(
                                                Text(person.emoji).font(.system(size: 18))
                                            )
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(person.name)
                                                .foregroundStyle(.white)
                                            
                                            if currentUser?.persistentModelID == person.persistentModelID {
                                                Text("Current User")
                                                    .font(.caption2)
                                                    .foregroundStyle(.appAccent)
                                            }
                                        }
                                        
                                        Spacer()
                                        let included = splitPeople.contains {
                                            $0.persistentModelID == person.persistentModelID
                                        }
                                        Image(systemName: included ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(included ? .appAccent : .textSecondary)
                                            .font(.system(size: 22))
                                    }
                                    .padding(.vertical, 2)
                                }
                                .swipeActions(edge: .leading) {
                                    if currentUser?.persistentModelID != person.persistentModelID {
                                        Button {
                                            currentUserID = person.personID
                                        } label: {
                                            Label("Set as Me", systemImage: "person.fill.checkmark")
                                        }
                                        .tint(.appAccent)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search people")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.appAccent)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showNewPerson) {
                NewPersonSheet(splitPeople: $splitPeople)
            }
        }
    }

    private func toggle(_ person: Person) {
        if let idx = splitPeople.firstIndex(where: { $0.persistentModelID == person.persistentModelID }) {
            splitPeople.remove(at: idx)
        } else {
            splitPeople.append(person)
        }
    }
}

// MARK: - NewPersonSheet

struct NewPersonSheet: View {
    @Binding var splitPeople: [Person]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedEmoji = "👤"
    @State private var selectedColor: String = Person.colorPalette[0]
    @State private var setAsCurrentUser = false
    @AppStorage("currentUserID") private var currentUserID: String = ""

    let emojiOptions = ["👤", "👨", "👩", "🧑", "👦", "👧", "🧔", "👱", "🧒", "🧕"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    // Avatar preview
                    Circle()
                        .fill(Color(hex: selectedColor))
                        .frame(width: 80, height: 80)
                        .overlay(Text(selectedEmoji).font(.system(size: 40)))
                        .padding(.top, 12)

                    // Name field
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)

                    // Emoji picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EMOJI")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.textSecondary)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(emojiOptions, id: \.self) { emoji in
                                    Button(action: { selectedEmoji = emoji }) {
                                        Text(emoji)
                                            .font(.title2)
                                            .frame(width: 48, height: 48)
                                            .background(
                                                selectedEmoji == emoji
                                                    ? Color.appAccent.opacity(0.3)
                                                    : Color.cardBackground
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(
                                                        selectedEmoji == emoji ? Color.appAccent : .clear,
                                                        lineWidth: 1.5
                                                    )
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("COLOR")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.textSecondary)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Person.colorPalette, id: \.self) { hex in
                                    Button(action: { selectedColor = hex }) {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 36, height: 36)
                                            .overlay(
                                                Circle()
                                                    .stroke(.white, lineWidth: selectedColor == hex ? 2.5 : 0)
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    
                    // Set as current user toggle
                    Toggle(isOn: $setAsCurrentUser) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("This is me")
                                .foregroundStyle(.white)
                                .fontWeight(.medium)
                            Text("Automatically add to new splits")
                                .font(.caption)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    .tint(.appAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)

                    Spacer()
                }
            }
            .navigationTitle("New Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") { save() }
                        .foregroundStyle(.appAccent)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                selectedColor = Person.nextColor(avoiding: splitPeople)
                // Auto-enable "This is me" if no current user is set
                setAsCurrentUser = currentUserID.isEmpty
            }
        }
    }

    private func save() {
        let person = Person(
            name: name.trimmingCharacters(in: .whitespaces),
            emoji: selectedEmoji,
            color: selectedColor
        )
        modelContext.insert(person)
        splitPeople.append(person)
        
        // Set as current user if toggle is on
        if setAsCurrentUser {
            currentUserID = person.personID
        }
        
        dismiss()
    }
}

// MARK: - AddItemSheet (dark-styled reuse)

struct AddItemSheet: View {
    @Bindable var item: LineItem
    @Environment(\.dismiss) private var dismiss
    let onSave: (LineItem) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                Form {
                    Section {
                        TextField("Item Name", text: $item.name)
                            .foregroundStyle(.white)
                        HStack {
                            Text("$")
                                .foregroundStyle(.textSecondary)
                            TextField("0.00", value: $item.price, format: .number)
                                .keyboardType(.decimalPad)
                        }
                        Stepper(value: $item.quantity, in: 1...100) {
                            HStack {
                                Text("Quantity")
                                Spacer()
                                Text("\(item.quantity)")
                                    .foregroundStyle(.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.cardBackground)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(item.name.isEmpty ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(item)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.appAccent)
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
