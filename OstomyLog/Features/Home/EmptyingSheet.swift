import SwiftUI
import SwiftData

/// Logging an emptying. **The speed of this one screen is the product.**
///
/// It happens four to eight times a day, usually standing up, often at three in the morning. So
/// the sheet opens straight onto the volumes and a tap on one of them saves the record and
/// closes — two taps from the home screen, with no keyboard and no Save button to hunt for.
/// Everything else (the time, the consistency, a note) is behind "Add detail", where it costs
/// nothing to the person who just wants the number in.
struct EmptyingSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    @AppStorage(StomaProfile.Key.volumeUnit, store: WidgetSnapshot.defaults)
    private var volumeUnitRaw = VolumeUnit.millilitres.rawValue
    @AppStorage(StomaProfile.Key.stomaType, store: WidgetSnapshot.defaults)
    private var stomaTypeRaw = StomaType.ileostomy.rawValue

    @State private var detailed = false
    @State private var date: Date = .now
    @State private var customVolume: Double = 0
    @State private var character: OutputCharacter?
    @State private var notes = ""
    @State private var selectedVolume: Double?
    @FocusState private var customFocused: Bool

    private var unit: VolumeUnit { VolumeUnit(rawValue: volumeUnitRaw) ?? .millilitres }
    private var stomaType: StomaType { StomaType(rawValue: stomaTypeRaw) ?? .ileostomy }

    /// Volume buttons in whichever unit the user reads, so nobody is asked to tap "1.7 fl oz".
    private var quickValues: [Double] {
        switch unit {
        case .millilitres: return StomaProfile.defaultQuickVolumes
        case .fluidOunces: return [2, 4, 6, 8, 10, 12, 16].map(Volume.millilitres(fromFluidOunces:))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("How much came out?")
                        .font(.headline)
                        .padding(.top, 4)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(quickValues, id: \.self) { value in
                            Button {
                                if detailed {
                                    selectedVolume = value
                                } else {
                                    save(volumeML: value)
                                }
                            } label: {
                                Text(Volume.format(millilitres: value, in: unit))
                                    .font(.headline)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(background(for: value), in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(selectedVolume == value ? .white : Color.appAccent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("volume-\(Int(value.rounded()))")
                        }
                    }

                    customRow

                    if detailed {
                        detailSection
                    } else {
                        Button {
                            withAnimation { detailed = true }
                        } label: {
                            Label("Add detail", systemImage: "slider.horizontal.3")
                                .font(.subheadline)
                        }
                        Text("A tap on a volume saves it straight away. Add detail if you want to change the time, record the \(stomaType.characterLabel.lowercased()), or leave a note.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log emptying")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if detailed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save(volumeML: selectedVolume ?? customVolume) }
                            .bold()
                            .disabled((selectedVolume ?? customVolume) <= 0)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func background(for value: Double) -> Color {
        selectedVolume == value ? Color.appAccent : Color(.secondarySystemGroupedBackground)
    }

    private var customRow: some View {
        HStack(spacing: 10) {
            Text("Other")
                .font(.subheadline.weight(.medium))
            TextField("Amount", value: $customVolume, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($customFocused)
                .accessibilityIdentifier("customVolume")
            Text(unit.short)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Save") {
                save(volumeML: unit == .millilitres ? customVolume : Volume.millilitres(fromFluidOunces: customVolume))
            }
            .buttonStyle(.borderedProminent)
            .disabled(customVolume <= 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DatePicker("When", selection: $date)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 8) {
                Text(stomaType.characterLabel)
                    .font(.subheadline.weight(.semibold))
                OptionalChoiceChips(options: OutputCharacter.options(for: stomaType),
                                    selection: $character) { $0.name }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.subheadline.weight(.semibold))
                TextField("Optional", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func save(volumeML: Double) {
        guard volumeML > 0 else { return }
        let event = OstomyEvent(kind: .emptying, date: detailed ? date : .now)
        event.volumeML = volumeML
        event.character = character
        event.notes = notes
        context.insert(event)
        try? context.save()
        ReviewPrompter.recordSuccess(request: requestReview)
        dismiss()
    }
}

/// Chips where the selection can be cleared by tapping the chosen one again, for the fields that
/// are genuinely optional. Built on `ChoiceChips` so it wraps rather than truncating (rule 18).
struct OptionalChoiceChips<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value?
    var title: (Value) -> String

    var body: some View {
        Wrap(spacing: 8, lineSpacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = isSelected ? nil : option
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 30)
                        .background(isSelected ? Color.appAccent.opacity(0.18) : Color(.tertiarySystemFill),
                                    in: Capsule())
                        .foregroundStyle(isSelected ? Color.appAccent : Color.primary)
                        .overlay(Capsule().strokeBorder(isSelected ? Color.appAccent.opacity(0.55) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
