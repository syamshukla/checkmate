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
                        // Only show people section if we have people
                        if !splitPeople.isEmpty {
                            peopleManagementSection
                            evenSplitRow
                        }
                        itemsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, splitPeople.isEmpty ? 140 : 200)
                }
            }

            // Bottom person selector OR add people button
            if splitPeople.isEmpty {
                addPeoplePrompt
            } else {
                personSelectorFooter
            }
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

    // MARK: - People Management Section (top, collapsible)
    
    var peopleManagementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("PEOPLE", systemImage: "person.2.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.textSecondary)
                Spacer()
                Button(action: { showPeoplePicker = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.caption)
                    .foregroundStyle(.appAccent)
                }
            }
            
            // People chips (non-interactive here, just for management)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(splitPeople) { person in
                        HStack(spacing: 8) {
                            Text(person.emoji)
                                .font(.title3)
                            Text(person.name)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(hex: person.color).opacity(0.3))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color(hex: person.color), lineWidth: 1)
                        )
                        .onLongPressGesture { removePerson(person) }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Add People Prompt (when empty)
    
    var addPeoplePrompt: some View {
        VStack(spacing: 0) {
            Button(action: { showPeoplePicker = true }) {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(.appAccent)
                    Text("Add people to start splitting")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Tap to select who's on this bill")
                        .font(.subheadline)
                        .foregroundStyle(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color.cardBackground)
            }
        }
        .background(.ultraThinMaterial.opacity(0.01))
        .background(Color.appBackground.opacity(0.98))
    }
    
    // MARK: - Person Selector Footer (bottom bar with people)
    
    var personSelectorFooter: some View {
        VStack(spacing: 0) {
            // Thin separator line
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
            
            // Person selector row (minimal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
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
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.appBackground.opacity(0.95))
            
            // Continue button (compact, slides up when ready)
            if canProceed {
                Button(action: { showCharges = true }) {
                    HStack(spacing: 8) {
                        Text("Continue")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.appBackground.opacity(0.95))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
            VStack(spacing: 10) {
                ForEach(receipt.lineItems) { item in
                    ItemRow(
                        item: item,
                        splitPeople: splitPeople,
                        activePerson: activePerson
                    ) {
                        handleItemTap(item)
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
        .padding(20)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        var total = 0.0
        for item in receipt.lineItems {
            guard !item.assignedPeople.isEmpty,
                  item.assignedPeople.contains(where: { $0.persistentModelID == person.persistentModelID })
            else { continue }
            total += item.totalPrice / Double(item.assignedPeople.count)
        }
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
    }
}

// MARK: - PersonSelectorChip (Bottom Bar)

struct PersonSelectorChip: View {
    let person: Person
    let isActive: Bool
    let subtotal: String

    var body: some View {
        VStack(spacing: 8) {
            // Avatar with glow effect
            ZStack {
                if isActive {
                    Circle()
                        .fill(Color(hex: person.color))
                        .frame(width: 72, height: 72)
                        .blur(radius: 20)
                        .opacity(0.6)
                }
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isActive 
                                ? [Color(hex: person.color), Color(hex: person.color).opacity(0.8)]
                                : [Color(hex: person.color).opacity(0.4), Color(hex: person.color).opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: isActive 
                                        ? [Color.white.opacity(0.6), Color.white.opacity(0.2)]
                                        : [Color.white.opacity(0.2), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                Text(person.emoji)
                    .font(.system(size: 26))
            }
            .scaleEffect(isActive ? 1.08 : 1.0)
            
            // Name and subtotal
            VStack(spacing: 2) {
                Text(person.name)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .medium)
                    .foregroundStyle(isActive ? .white : .textSecondary)
                
                Text(subtotal)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(isActive ? Color(hex: person.color) : .textSecondary.opacity(0.6))
            }
        }
        .frame(width: 76)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
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
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name.isEmpty ? "Unnamed Item" : item.name)
                        .foregroundStyle(.white)
                        .fontWeight(.medium)
                        .font(.body)
                    if item.quantity > 1 {
                        Text("\(item.quantity) × \(String(format: "$%.2f", item.price))")
                            .font(.caption)
                            .foregroundStyle(.textSecondary)
                    }
                }

                Spacer()

                Text(String(format: "$%.2f", item.totalPrice))
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
                    .font(.title3)

                assignmentIndicator
            }
            .padding(16)
            .background(
                ZStack {
                    // Base background
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.elevatedCard)
                    
                    // Active person overlay
                    if let active = activePerson, isAssignedToActive {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: active.color).opacity(0.25),
                                        Color(hex: active.color).opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        activePerson.map { active in
                            isAssignedToActive 
                                ? Color(hex: active.color).opacity(0.8)
                                : Color.clear
                        } ?? .clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: item.assignedPeople.map { $0.persistentModelID })
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: activePerson?.persistentModelID)
    }
    
    @ViewBuilder
    var assignmentIndicator: some View {
        if splitPeople.isEmpty {
            EmptyView()
        } else if item.assignedPeople.isEmpty {
            Circle()
                .fill(Color.textSecondary.opacity(0.3))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .strokeBorder(Color.textSecondary.opacity(0.5), lineWidth: 2, antialiased: true)
                        .padding(2)
                )
        } else if isEveryoneAssigned {
            ZStack {
                Circle()
                    .fill(Color.appAccent)
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        } else {
            ZStack {
                Circle()
                    .fill(Color.elevatedCard)
                    .frame(width: 28, height: 28)
                
                ForEach(Array(item.assignedPeople.prefix(1)), id: \.persistentModelID) { person in
                    Text(person.emoji)
                        .font(.system(size: 14))
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

    var perPersonAmount: String {
        guard !item.assignedPeople.isEmpty else { return "" }
        let amt = item.totalPrice / Double(item.assignedPeople.count)
        return String(format: "$%.2f each", amt)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Item summary
                        HStack {
                            Text(item.name.isEmpty ? "Item" : item.name)
                                .foregroundStyle(.white)
                                .fontWeight(.semibold)
                                .font(.title3)
                            Spacer()
                            Text(String(format: "$%.2f", item.totalPrice))
                                .foregroundStyle(.white)
                                .fontWeight(.semibold)
                                .font(.title3)
                        }
                        .padding(16)
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        // Per-person cost pill
                        if !item.assignedPeople.isEmpty {
                            Text(perPersonAmount)
                                .font(.headline)
                                .foregroundStyle(.appAccent)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(Color.appAccent.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Everyone button
                        if !splitPeople.isEmpty {
                            Button(action: {
                                item.assignedPeople = splitPeople
                            }) {
                                HStack {
                                    Image(systemName: "person.3.fill")
                                    Text("Everyone")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .background(Color.appAccent)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        // Per-person toggles
                        VStack(spacing: 10) {
                            ForEach(splitPeople) { person in
                                let assigned = item.assignedPeople.contains {
                                    $0.persistentModelID == person.persistentModelID
                                }
                                Button(action: {
                                    if assigned {
                                        item.assignedPeople.removeAll {
                                            $0.persistentModelID == person.persistentModelID
                                        }
                                    } else {
                                        item.assignedPeople.append(person)
                                    }
                                }) {
                                    HStack(spacing: 14) {
                                        Circle()
                                            .fill(Color(hex: person.color))
                                            .frame(width: 38, height: 38)
                                            .overlay(Text(person.emoji).font(.system(size: 18)))
                                        Text(person.name)
                                            .foregroundStyle(.white)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Image(systemName: assigned ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(assigned ? Color(hex: person.color) : .textSecondary)
                                            .font(.system(size: 22))
                                    }
                                    .padding(14)
                                    .background(
                                        assigned
                                            ? Color(hex: person.color).opacity(0.15)
                                            : Color.cardBackground
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(assigned ? Color(hex: person.color).opacity(0.5) : .clear, lineWidth: 1)
                                    )
                                }
                            }
                        }

                        Spacer()
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
}

// MARK: - PeoplePickerView

struct PeoplePickerView: View {
    @Binding var splitPeople: [Person]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.name) private var allPeople: [Person]
    @State private var searchText = ""
    @State private var showNewPerson = false

    var filtered: [Person] {
        searchText.isEmpty ? allPeople
            : allPeople.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                                        Text(person.name)
                                            .foregroundStyle(.white)
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
            }
        }
    }

    private func save() {
        let person = Person(name: name.trimmingCharacters(in: .whitespaces), emoji: selectedEmoji, color: selectedColor)
        modelContext.insert(person)
        splitPeople.append(person)
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
