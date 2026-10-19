import SwiftUI
import SwiftData

/// What is in the cupboard, and how long it lasts at the rate the user is actually changing.
///
/// Free text on purpose. The manufacturer apps are free because they exist to reorder that
/// manufacturer's catalogue, which is no help to somebody wearing a barrier from one company, a
/// belt from another and pouches from wherever the supplier had stock. Type what is on the box.
struct SuppliesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SupplyItem.name) private var supplies: [SupplyItem]
    @Query(sort: \OstomyEvent.date, order: .reverse) private var events: [OstomyEvent]

    @State private var editingItem: SupplyItem?
    @State private var addingItem = false

    private var rates: UsageRates { UsageRates.measured(from: events) }

    var body: some View {
        Group {
            if supplies.isEmpty {
                ContentUnavailableView {
                    Label("No supplies yet", systemImage: "shippingbox")
                } description: {
                    Text("Add what you use — the name and size off the box — and how many you have left. The countdown comes from how often you have actually been changing.")
                } actions: {
                    Button("Add a supply") { addingItem = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("addSupplyEmptyState")
                }
            } else {
                List {
                    Section {
                        ForEach(supplies) { item in
                            Button { editingItem = item } label: { SupplyRow(item: item, rates: rates) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(supplies[index]) }
                            try? context.save()
                        }
                    } footer: {
                        Text(rateFooter)
                    }
                }
            }
        }
        .navigationTitle("Supplies")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingItem = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a supply")
                    .accessibilityIdentifier("addSupply")
            }
        }
        .sheet(isPresented: $addingItem) { SupplyEditorView(item: nil) }
        .sheet(item: $editingItem) { SupplyEditorView(item: $0) }
    }

    private var rateFooter: String {
        guard rates.barrierChangesPerDay > 0 else {
            return "Log two appliance changes and the app can work out your rate. Until then it says so rather than guessing."
        }
        let everyDays = 1 / rates.barrierChangesPerDay
        return String(format: "At your recent rate you change the barrier about every %.1f days. The countdown uses that, not a schedule this app invented.", everyDays)
    }
}

private struct SupplyRow: View {
    let item: SupplyItem
    let rates: UsageRates

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(item.quantityOnHand) on hand · \(item.quantityPerUse) per use · \(item.basis.name.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(countdown)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var days: Int? { item.daysRemaining(rates: rates) }

    private var countdown: String {
        guard let days else { return "No rate yet" }
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    private var tint: Color {
        guard let days else { return .secondary }
        return days <= 7 ? .appBadge : .primary
    }
}

/// Add or edit one supply.
struct SupplyEditorView: View {
    let item: SupplyItem?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var size = ""
    @State private var quantityOnHand = 0
    @State private var quantityPerUse = 1
    @State private var basis: SupplyBasis = .barrierChange
    @State private var notes = ""
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is it", text: $name)
                        .focused($nameFocused)
                    TextField("Size or cut, as written on the box", text: $size)
                } footer: {
                    Text("Your words, not a brand list. \"Barrier, cut-to-fit 20 to 45 mm\" is a perfectly good name.")
                }

                Section("How many") {
                    Stepper("On hand: \(quantityOnHand)", value: $quantityOnHand, in: 0...999)
                    Stepper("Used each time: \(quantityPerUse)", value: $quantityPerUse, in: 1...20)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Used at").font(.subheadline.weight(.semibold))
                        ChoiceChips(options: SupplyBasis.allCases, selection: $basis) { $0.name }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("The countdown divides what you have left by how often this happens in your own log.")
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let item {
                    Section {
                        Button("Delete this supply", role: .destructive) {
                            context.delete(item)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "Add a supply" : "Edit supply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold().disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                guard let item else { nameFocused = true; return }
                name = item.name
                size = item.size
                quantityOnHand = item.quantityOnHand
                quantityPerUse = item.quantityPerUse
                basis = item.basis
                notes = item.notes
            }
        }
    }

    private func save() {
        let record = item ?? SupplyItem()
        record.name = name.trimmingCharacters(in: .whitespaces)
        record.size = size.trimmingCharacters(in: .whitespaces)
        record.quantityOnHand = quantityOnHand
        record.quantityPerUse = quantityPerUse
        record.basis = basis
        record.notes = notes
        record.updatedAt = .now
        if item == nil { context.insert(record) }
        try? context.save()
        dismiss()
    }
}
