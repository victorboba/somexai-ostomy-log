import SwiftUI
import SwiftData

/// The home screen is a status board, not a list.
///
/// Somebody with a new stoma opens this app four to eight times a day, standing in a bathroom,
/// to record one number. So the screen answers the two questions they have at that moment —
/// how much has come out today, and how long has this barrier been on — and puts the emptying
/// button under the thumb. The history is a tap away; it is not the thing that greets them.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \OstomyEvent.date, order: .reverse) private var events: [OstomyEvent]
    @Query(sort: \SupplyItem.name) private var supplies: [SupplyItem]

    @AppStorage(StomaProfile.Key.volumeUnit, store: WidgetSnapshot.defaults)
    private var volumeUnitRaw = VolumeUnit.millilitres.rawValue
    @AppStorage(StomaProfile.Key.dailyOutputTargetML, store: WidgetSnapshot.defaults)
    private var dailyTargetML: Double = 0

    @State private var loggingEmptying = false
    @State private var newEventKind: EventKind?
    @State private var editingEvent: OstomyEvent?
    @State private var showingSettings = false
    @State private var exportFile: ExportFile?
    @State private var exportError: String?

    private var unit: VolumeUnit { VolumeUnit(rawValue: volumeUnitRaw) ?? .millilitres }
    private var today: (millilitres: Double, emptyings: Int) { WearClock.outputToday(in: events) }
    private var wearHours: Double? { WearClock.hoursOn(in: events) }
    private var recent: LogSummary { LogSummary.recent(events, days: 30) }
    private var rates: UsageRates { UsageRates.measured(from: events) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    logEmptyingButton
                    secondaryButtons
                    suppliesCard
                    recentCard
                    historyLink
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                    NavigationLink { HowToView() } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("How do I use this app?")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Appointment PDF, last 30 days", systemImage: "doc.richtext") { exportPDF(days: 30) }
                        Button("Appointment PDF, last 90 days", systemImage: "doc.richtext") { exportPDF(days: 90) }
                        Button("Every record as CSV", systemImage: "tablecells") { exportCSV() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(events.isEmpty)
                    .accessibilityLabel("Export")
                }
            }
            .sheet(isPresented: $loggingEmptying) { EmptyingSheet() }
            .sheet(item: $newEventKind) { kind in EventEditorView(kind: kind, event: nil) }
            .sheet(item: $editingEvent) { event in EventEditorView(kind: event.kind, event: event) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(item: $exportFile) { ShareSheet(url: $0.url) }
            .alert("Export failed", isPresented: .constant(exportError != nil)) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
        }
        .onChange(of: events.count, initial: true) { syncWidget() }
        .onChange(of: supplies.count) { syncWidget() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            syncWidget()
            openEmptyingIfRequestedByShortcut()
        }
    }

    // MARK: The two live numbers

    private var statusCard: some View {
        DashboardCard {
            HStack(alignment: .center, spacing: 18) {
                WearRing(hours: wearHours, averageHours: recent.averageWearHours)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Volume.format(millilitres: today.millilitres, in: unit))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .accessibilityIdentifier("outputToday")
                    Text(today.emptyings == 1 ? "1 emptying" : "\(today.emptyings) emptyings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if dailyTargetML > 0 {
                        Text("Your target \(Volume.format(millilitres: dailyTargetML, in: unit))")
                            .font(.caption)
                            .foregroundStyle(Color.appAccent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: The action the app exists for

    private var logEmptyingButton: some View {
        Button {
            loggingEmptying = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill").font(.title2)
                Text("Log emptying")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("logEmptying")
        .contextMenu {
            if let last = events.first(where: { $0.kind == .emptying }) {
                Button("Repeat \(Volume.format(millilitres: last.volumeML, in: unit))",
                       systemImage: "arrow.counterclockwise") {
                    repeatLastEmptying(last)
                }
            }
        }
    }

    private var secondaryButtons: some View {
        HStack(spacing: 10) {
            ForEach([EventKind.applianceChange, .leak, .skinCheck]) { kind in
                Button { newEventKind = kind } label: {
                    VStack(spacing: 6) {
                        Image(systemName: kind.symbol).font(.headline)
                        Text(kind.name)
                            .font(.footnote.weight(.medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(Color.appAccent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("log-\(kind.rawValue)")
            }
        }
    }

    // MARK: Cards

    private var suppliesCard: some View {
        NavigationLink {
            SuppliesView()
        } label: {
            DashboardCard(title: "Supplies", symbol: "shippingbox") {
                if supplies.isEmpty {
                    Text("Add what you use and the app counts down from how often you actually change.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(soonestSupplies) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 10)
                                Text(supplyCountdown(item))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(supplyTint(item))
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var soonestSupplies: [SupplyItem] {
        supplies.sorted { lhs, rhs in
            (lhs.daysRemaining(rates: rates) ?? .max) < (rhs.daysRemaining(rates: rates) ?? .max)
        }.prefix(3).map { $0 }
    }

    private func supplyCountdown(_ item: SupplyItem) -> String {
        guard let days = item.daysRemaining(rates: rates) else { return "No rate yet" }
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    private func supplyTint(_ item: SupplyItem) -> Color {
        guard let days = item.daysRemaining(rates: rates) else { return .secondary }
        return days <= 7 ? .appBadge : .primary
    }

    private var recentCard: some View {
        NavigationLink {
            SummaryView()
        } label: {
            DashboardCard(title: "Last 30 days", symbol: "chart.bar.doc.horizontal") {
                VStack(alignment: .leading, spacing: 8) {
                    summaryLine("Average wear time",
                                recent.averageWearHours.map { WearTimeFormat.days(hours: $0) } ?? "Not enough changes yet")
                    summaryLine("Average daily output",
                                recent.averageDailyOutputML.map { Volume.format(millilitres: $0, in: unit) } ?? "No emptyings yet")
                    summaryLine("Changes", changesLine)
                    summaryLine("Leaks logged", "\(recent.leaks.count)")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var changesLine: String {
        let summary = recent
        guard !summary.changes.isEmpty else { return "None yet" }
        return "\(summary.plannedChanges) planned · \(summary.leakForcedChanges) after a leak"
    }

    private func summaryLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 10)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var historyLink: some View {
        NavigationLink {
            HistoryView()
        } label: {
            DashboardCard {
                HStack {
                    Label("Full history", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(events.isEmpty ? "Nothing yet" : "\(events.count) records")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func repeatLastEmptying(_ last: OstomyEvent) {
        let event = OstomyEvent(kind: .emptying, date: .now)
        event.volumeML = last.volumeML
        event.characterRaw = last.characterRaw
        context.insert(event)
        try? context.save()
        syncWidget()
    }

    private func exportPDF(days: Int) {
        do {
            let summary = LogSummary.recent(events, days: days)
            exportFile = ExportFile(url: try PDFExporter.export(summary: summary, supplies: supplies, rates: rates))
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportCSV() {
        do { exportFile = ExportFile(url: try CSVExporter.export(events)) }
        catch { exportError = error.localizedDescription }
    }

    private func syncWidget() {
        WidgetSync.update(events: events, supplies: supplies)
    }

    private func openEmptyingIfRequestedByShortcut() {
        let defaults = WidgetSnapshot.defaults
        guard defaults.bool(forKey: LogEmptyingIntent.pendingKey) else { return }
        defaults.removeObject(forKey: LogEmptyingIntent.pendingKey)
        loggingEmptying = true
    }
}

// MARK: - The wear-time ring

/// Elapsed time on the barrier currently worn, drawn against the user's own recent average.
///
/// The ring fills toward *their* average wear time, not toward a number this app invented. When
/// there is no average yet it fills toward three days purely so the arc has a scale, and the
/// caption says what it is measuring rather than implying a target.
struct WearRing: View {
    let hours: Double?
    let averageHours: Double?

    private var scale: Double { max(averageHours ?? 72, 12) }
    private var fraction: Double {
        guard let hours else { return 0 }
        return min(1, max(0, hours / scale))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.appAccent.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.appBadge, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(hours.map { WearTimeFormat.short(hours: $0) } ?? "—")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("worn")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .frame(width: 108, height: 108)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 118)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hours == nil
                            ? "No appliance change logged yet"
                            : "Barrier worn \(WearTimeFormat.short(hours: hours ?? 0))")
    }

    private var caption: String {
        guard hours != nil else { return "No change logged yet" }
        guard let averageHours else { return "Since your last change" }
        return "Your average \(WearTimeFormat.days(hours: averageHours))"
    }
}
