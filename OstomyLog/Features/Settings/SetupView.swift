import SwiftUI

/// What the user wears, which decides what the app asks them, plus the one figure that may only
/// ever come from their own clinician.
///
/// **The rule this screen exists to keep.** The daily output figure is typed in by the user
/// because somebody qualified gave it to them. The app stores it, labels it as theirs, and counts
/// days against it. It does not suggest a figure, does not fill one in by default, and does not
/// say anything about what being above or below it means.
struct SetupView: View {
    @AppStorage(StomaProfile.Key.stomaType, store: WidgetSnapshot.defaults)
    private var stomaTypeRaw = StomaType.ileostomy.rawValue
    @AppStorage(StomaProfile.Key.applianceSystem, store: WidgetSnapshot.defaults)
    private var applianceSystemRaw = ApplianceSystem.onePiece.rawValue
    @AppStorage(StomaProfile.Key.volumeUnit, store: WidgetSnapshot.defaults)
    private var volumeUnitRaw = VolumeUnit.millilitres.rawValue
    @AppStorage(StomaProfile.Key.dailyOutputTargetML, store: WidgetSnapshot.defaults)
    private var dailyTargetML: Double = 0

    @State private var targetEntry: Double = 0

    private var stomaType: Binding<StomaType> {
        Binding(get: { StomaType(rawValue: stomaTypeRaw) ?? .ileostomy },
                set: { stomaTypeRaw = $0.rawValue })
    }

    private var system: Binding<ApplianceSystem> {
        Binding(get: { ApplianceSystem(rawValue: applianceSystemRaw) ?? .onePiece },
                set: { applianceSystemRaw = $0.rawValue })
    }

    private var unit: Binding<VolumeUnit> {
        Binding(get: { VolumeUnit(rawValue: volumeUnitRaw) ?? .millilitres },
                set: { volumeUnitRaw = $0.rawValue })
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type of stoma").font(.subheadline.weight(.semibold))
                    ChoiceChips(options: StomaType.allCases, selection: stomaType) { $0.name }
                }
                .padding(.vertical, 4)
            } footer: {
                Text(stomaType.wrappedValue == .urostomy
                     ? "A urostomy is asked about appearance rather than consistency."
                     : "You will be asked for consistency on an ordinal scale, in plain words.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Appliance").font(.subheadline.weight(.semibold))
                    ChoiceChips(options: ApplianceSystem.allCases, selection: system) { $0.name }
                }
                .padding(.vertical, 4)
            } footer: {
                Text(system.wrappedValue.detail + (system.wrappedValue == .twoPiece
                     ? " Only a change that takes the barrier off restarts wear time."
                     : ""))
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Volumes shown in").font(.subheadline.weight(.semibold))
                    ChoiceChips(options: VolumeUnit.allCases, selection: unit) { $0.name }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Millilitres are what is stored either way, so switching never changes a record.")
            }

            Section {
                HStack {
                    TextField("None set", value: $targetEntry, format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("dailyTarget")
                    Text(unit.wrappedValue.short).foregroundStyle(.secondary)
                }
                Button("Save target") { saveTarget() }
                    .disabled(targetEntry < 0)
                if dailyTargetML > 0 {
                    Button("Remove the target", role: .destructive) {
                        dailyTargetML = 0
                        targetEntry = 0
                    }
                }
            } header: {
                Text("Daily output target your clinician gave you").textCase(nil)
            } footer: {
                Text("Only fill this in if your own WOC nurse, surgeon or dietitian gave you a figure. \(AppConfig.appName) never suggests one, never warns you about one, and never tells you what being over or under it means. It shows your days beside your own number, and that is all.")
            }
        }
        .navigationTitle("My setup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            targetEntry = unit.wrappedValue == .millilitres
                ? dailyTargetML
                : Volume.fluidOunces(fromMillilitres: dailyTargetML)
        }
    }

    private func saveTarget() {
        let millilitres = unit.wrappedValue == .millilitres
            ? targetEntry
            : Volume.millilitres(fromFluidOunces: targetEntry)
        dailyTargetML = max(0, millilitres)
    }
}
