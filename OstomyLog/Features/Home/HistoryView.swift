import SwiftUI
import SwiftData

/// Everything that has been logged, newest first, with each day's totals in its header.
///
/// The header is the point: a nurse reading over somebody's shoulder wants the day's total and
/// how many times, not twelve rows to add up.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \OstomyEvent.date, order: .reverse) private var events: [OstomyEvent]

    @AppStorage(StomaProfile.Key.volumeUnit, store: WidgetSnapshot.defaults)
    private var volumeUnitRaw = VolumeUnit.millilitres.rawValue

    @State private var editingEvent: OstomyEvent?
    @State private var filter: EventKind?

    private var unit: VolumeUnit { VolumeUnit(rawValue: volumeUnitRaw) ?? .millilitres }

    private var shown: [OstomyEvent] {
        guard let filter else { return events }
        return events.filter { $0.kind == filter }
    }

    private var grouped: [(day: Date, events: [OstomyEvent])] {
        let groups = Dictionary(grouping: shown, by: \.day)
        return groups.keys.sorted(by: >).map { (day: $0, events: (groups[$0] ?? []).sorted { $0.date > $1.date }) }
    }

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView {
                    Label("Nothing logged yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Emptyings, appliance changes, leaks and skin checks all land here.")
                }
            } else {
                List {
                    Section {
                        Wrap(spacing: 8, lineSpacing: 8) {
                            filterChip(nil, "Everything")
                            ForEach(EventKind.allCases) { kind in filterChip(kind, kind.plural) }
                        }
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }

                    ForEach(grouped, id: \.day) { group in
                        Section {
                            ForEach(group.events) { event in
                                Button { editingEvent = event } label: { HistoryRow(event: event, unit: unit) }
                                    .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                for index in offsets { context.delete(group.events[index]) }
                                try? context.save()
                            }
                        } header: {
                            DayHeader(day: group.day, events: events.filter { $0.day == group.day }, unit: unit)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingEvent) { event in EventEditorView(kind: event.kind, event: event) }
    }

    private func filterChip(_ kind: EventKind?, _ label: String) -> some View {
        let isSelected = filter == kind
        return Button { filter = kind } label: {
            Text(label)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(isSelected ? Color.appAccent.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(isSelected ? Color.appAccent : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct DayHeader: View {
    let day: Date
    let events: [OstomyEvent]
    let unit: VolumeUnit

    private var output: Double { events.filter { $0.kind == .emptying }.reduce(0) { $0 + $1.volumeML } }
    private var emptyings: Int { events.filter { $0.kind == .emptying }.count }
    private var changes: Int { events.filter { $0.kind == .applianceChange }.count }
    private var leaks: Int { events.filter { $0.kind == .leak }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.formatted(date: .complete, time: .omitted))
                .font(.footnote.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts: [String] = []
        if emptyings > 0 {
            parts.append("\(Volume.format(millilitres: output, in: unit)) over \(emptyings) \(emptyings == 1 ? "emptying" : "emptyings")")
        }
        if changes > 0 { parts.append("\(changes) \(changes == 1 ? "change" : "changes")") }
        if leaks > 0 { parts.append("\(leaks) \(leaks == 1 ? "leak" : "leaks")") }
        return parts.isEmpty ? "No emptyings recorded" : parts.joined(separator: " · ")
    }
}

private struct HistoryRow: View {
    let event: OstomyEvent
    let unit: VolumeUnit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.symbol)
                .font(.footnote)
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.15), in: Circle())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !event.notes.isEmpty, event.kind != .leak {
                    Text(event.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Text(event.date.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var headline: String {
        switch event.kind {
        case .emptying: return Volume.format(millilitres: event.volumeML, in: unit)
        default: return "\(event.kind.name): \(event.headline)"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .emptying: return .appAccent
        case .applianceChange: return .appAccentLight
        case .leak: return .appBadge
        case .skinCheck: return .purple
        }
    }
}
