import SwiftUI
import SwiftData

/// Add or edit anything that is not a two-tap emptying: an appliance change, a leak, a skin check
/// — and an emptying when the user goes back to correct one.
///
/// The appliance change is the one that carries weight. The moment it is saved the app works out
/// how long the barrier that just came off had been on, from the previous barrier change in the
/// log, and stamps it on the record. That number is what the nurse asks for, and it is arithmetic
/// on the user's own entries: the app never suggests how long a barrier ought to last.
struct EventEditorView: View {
    let kind: EventKind
    let event: OstomyEvent?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Query(sort: \OstomyEvent.date, order: .reverse) private var allEvents: [OstomyEvent]

    @AppStorage(StomaProfile.Key.volumeUnit, store: WidgetSnapshot.defaults)
    private var volumeUnitRaw = VolumeUnit.millilitres.rawValue
    @AppStorage(StomaProfile.Key.stomaType, store: WidgetSnapshot.defaults)
    private var stomaTypeRaw = StomaType.ileostomy.rawValue
    @AppStorage(StomaProfile.Key.applianceSystem, store: WidgetSnapshot.defaults)
    private var applianceSystemRaw = ApplianceSystem.onePiece.rawValue

    @State private var date: Date = .now
    @State private var volume: Double = 0
    @State private var character: OutputCharacter?
    @State private var scope: ChangeScope = .whole
    @State private var reason: ChangeReason = .planned
    @State private var leakCause: LeakCause?
    @State private var skin: SkinCondition?
    @State private var notes = ""
    @State private var photoData: Data?
    @State private var loaded = false

    private var unit: VolumeUnit { VolumeUnit(rawValue: volumeUnitRaw) ?? .millilitres }
    private var stomaType: StomaType { StomaType(rawValue: stomaTypeRaw) ?? .ileostomy }
    private var system: ApplianceSystem { ApplianceSystem(rawValue: applianceSystemRaw) ?? .onePiece }

    /// What will be written on this change if it is saved as it stands.
    private var projectedWearHours: Double {
        WearClock.wearHours(forChangeAt: date, scope: scope, in: allEvents, excluding: event)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("When", selection: $date)
                }

                switch kind {
                case .emptying: emptyingSection
                case .applianceChange: changeSection
                case .leak: leakSection
                case .skinCheck: skinSection
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if kind == .leak || kind == .skinCheck {
                    Section {
                        PhotoField(data: $photoData,
                                   label: kind == .leak ? "Photo of the leak" : "Photo of the skin")
                    } footer: {
                        Text("Photos stay on this phone. They are never uploaded and they are not put into the exported PDF — send one yourself if you want your nurse to see it.")
                    }
                }

                if let event {
                    Section {
                        Button("Delete this record", role: .destructive) {
                            context.delete(event)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(event == nil ? kind.name : "Edit \(kind.name.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold().disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var canSave: Bool {
        kind != .emptying || volume > 0
    }

    // MARK: Sections

    private var emptyingSection: some View {
        Section("Volume") {
            HStack {
                TextField("Amount", value: $volume, format: .number)
                    .keyboardType(.decimalPad)
                Text(unit.short).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(stomaType.characterLabel).font(.subheadline.weight(.semibold))
                OptionalChoiceChips(options: OutputCharacter.options(for: stomaType),
                                    selection: $character) { $0.name }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var changeSection: some View {
        if system.changeScopes.count > 1 {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What came off").font(.subheadline.weight(.semibold))
                    ChoiceChips(options: system.changeScopes, selection: $scope) { $0.name }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Wear time belongs to the barrier. Changing only the pouch leaves the barrier on the skin, so it does not restart the clock.")
            }
        }

        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Why").font(.subheadline.weight(.semibold))
                ChoiceChips(options: ChangeReason.allCases, selection: $reason) { $0.name }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Planned against forced is the most useful line in the whole report, so it is worth being honest about.")
        }

        if scope.includesBarrier {
            Section("Wear time") {
                LabeledContent("This barrier was on",
                               value: projectedWearHours > 0
                               ? WearTimeFormat.short(hours: projectedWearHours)
                               : "First recorded change")
            }
        }
    }

    private var leakSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("What do you think caused it?").font(.subheadline.weight(.semibold))
                OptionalChoiceChips(options: LeakCause.allCases, selection: $leakCause) { $0.name }
            }
            .padding(.vertical, 4)
        }
    }

    private var skinSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("How does the skin around the stoma look?")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                OptionalChoiceChips(options: SkinCondition.allCases, selection: $skin) { $0.name }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Your own description, in your own words. \(AppConfig.appName) records it and never interprets it.")
        }
    }

    // MARK: Load and save

    private func load() {
        guard !loaded else { return }
        loaded = true
        if system.changeScopes.count == 1 { scope = system.changeScopes[0] }
        guard let event else { return }
        date = event.date
        volume = unit == .millilitres ? event.volumeML : Volume.fluidOunces(fromMillilitres: event.volumeML)
        character = event.character
        scope = event.scope
        reason = event.reason
        leakCause = event.leakCause
        skin = event.skin
        notes = event.notes
        photoData = event.photoData
    }

    private func save() {
        let record = event ?? OstomyEvent(kind: kind, date: date)
        record.kind = kind
        record.date = date
        record.notes = notes
        record.photoData = photoData

        switch kind {
        case .emptying:
            record.volumeML = unit == .millilitres ? volume : Volume.millilitres(fromFluidOunces: volume)
            record.character = character
        case .applianceChange:
            record.scope = system.changeScopes.contains(scope) ? scope : system.changeScopes[0]
            record.reason = reason
            record.wearHours = WearClock.wearHours(forChangeAt: date, scope: record.scope,
                                                   in: allEvents, excluding: event)
        case .leak:
            record.leakCause = leakCause
        case .skinCheck:
            record.skin = skin
        }

        if event == nil { context.insert(record) }
        try? context.save()
        ReviewPrompter.recordSuccess(request: requestReview)
        dismiss()
    }
}
