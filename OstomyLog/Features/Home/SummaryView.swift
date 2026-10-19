import SwiftUI
import SwiftData

/// The numbers, over a period the user picks. Every one of them is a statement about what they
/// typed in — a total, an average, a count, a ratio — and nothing here says whether a number is
/// good or bad. Where they have entered a figure their own clinician gave them, it is labelled
/// as theirs and their days are counted against it.
struct SummaryView: View {
    @Query(sort: \OstomyEvent.date, order: .reverse) private var events: [OstomyEvent]
    @Query(sort: \SupplyItem.name) private var supplies: [SupplyItem]

    @AppStorage(StomaProfile.Key.volumeUnit, store: WidgetSnapshot.defaults)
    private var volumeUnitRaw = VolumeUnit.millilitres.rawValue
    @AppStorage(StomaProfile.Key.dailyOutputTargetML, store: WidgetSnapshot.defaults)
    private var dailyTargetML: Double = 0

    @State private var days = 30
    @State private var exportFile: ExportFile?
    @State private var exportError: String?

    private var unit: VolumeUnit { VolumeUnit(rawValue: volumeUnitRaw) ?? .millilitres }
    private var summary: LogSummary { LogSummary.recent(events, days: days) }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $days) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)
            }

            Section("Output") {
                row("Total", summary.emptyings.isEmpty ? "No emptyings" : Volume.formatBoth(millilitres: summary.totalOutputML))
                row("Average a day", summary.averageDailyOutputML.map { Volume.formatBoth(millilitres: $0) } ?? "—")
                row("Emptyings a day", summary.averageEmptyingsPerDay.map { String(format: "%.1f", $0) } ?? "—")
                row("Average an emptying", summary.averageVolumePerEmptyingML.map { Volume.format(millilitres: $0, in: unit) } ?? "—")
                row("Days with a record", "\(summary.daysWithOutput)")
            }

            if let target = summary.daysOverTarget(dailyTargetML > 0 ? dailyTargetML : nil) {
                Section {
                    row("Days above it", "\(target.over) of \(target.counted)")
                } header: {
                    Text("Your own target, \(Volume.format(millilitres: dailyTargetML, in: unit)) a day")
                        .textCase(nil)
                } footer: {
                    Text("This is the figure you entered under My setup because your own clinician gave it to you. \(AppConfig.appName) counts your days against it and nothing more.")
                }
            }

            Section {
                row("Average wear time", summary.averageWearHours.map { WearTimeFormat.days(hours: $0) } ?? "Not enough changes yet")
                row("Shortest", summary.shortestWearHours.map { WearTimeFormat.short(hours: $0) } ?? "—")
                row("Longest", summary.longestWearHours.map { WearTimeFormat.short(hours: $0) } ?? "—")
                row("Barrier changes", "\(summary.barrierChanges.count)")
            } header: {
                Text("Wear time").textCase(nil)
            } footer: {
                Text("Measured from one barrier change to the next. A change with nothing before it to measure from is left out.")
            }

            Section {
                row("Planned", "\(summary.plannedChanges)")
                row("After a leak", "\(summary.leakForcedChanges)")
                row("Forced, any reason", "\(summary.forcedChanges)")
                if let share = summary.forcedShare {
                    row("Share forced", "\(Int((share * 100).rounded()))%")
                }
            } header: {
                Text("Planned against forced").textCase(nil)
            }

            Section("Leaks and skin") {
                row("Leaks logged", "\(summary.leaks.count)")
                row("Skin checks", "\(summary.skinChecks.count)")
                if let worst = summary.skinChecks.compactMap(\.skin).max(by: { $0.rank < $1.rank }) {
                    row("Most marked", worst.name)
                }
            }

            Section {
                Button {
                    exportPDF()
                } label: {
                    Label("Appointment PDF for this period", systemImage: "doc.richtext")
                }
                Button {
                    exportCSV()
                } label: {
                    Label("Every record as CSV", systemImage: "tablecells")
                }
            } footer: {
                Text("The PDF puts daily totals, wear times, leaks and skin notes on one page for your appointment. Photos are not included; they stay on this phone.")
            }
        }
        .navigationTitle("Last \(days) days")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportFile) { ShareSheet(url: $0.url) }
        .alert("Export failed", isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exportPDF() {
        do {
            exportFile = ExportFile(url: try PDFExporter.export(
                summary: summary, supplies: supplies,
                rates: UsageRates.measured(from: events)))
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportCSV() {
        do { exportFile = ExportFile(url: try CSVExporter.export(events)) }
        catch { exportError = error.localizedDescription }
    }
}
