import WidgetKit
import SwiftUI

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        // Wear time moves every hour and the day rolls over at midnight, so refresh on the hour.
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

/// The two numbers the home screen leads with, on the Home Screen: what has come out today, and
/// how long the barrier has been on.
struct OstomyLogWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var unit: VolumeUnit { StomaProfile.volumeUnit }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Volume.format(millilitres: entry.snapshot.outputTodayML, in: unit))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(entry.snapshot.emptyingsToday == 1 ? "1 emptying" : "\(entry.snapshot.emptyingsToday) emptyings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(wornLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if family != .systemSmall {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    label("Worn", wornValue)
                    if entry.snapshot.averageWearHours > 0 {
                        label("Your average", WearTimeFormat.days(hours: entry.snapshot.averageWearHours))
                    }
                    if let days = entry.snapshot.daysOfSuppliesLeft {
                        label("Supplies", days == 1 ? "1 day left" : "\(days) days left")
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func label(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var wornValue: String {
        entry.snapshot.wearHours(asOf: entry.date).map { WearTimeFormat.short(hours: $0) } ?? "No change logged"
    }

    private var wornLine: String {
        entry.snapshot.wearHours(asOf: entry.date).map { "Worn \(WearTimeFormat.short(hours: $0))" }
            ?? "No change logged yet"
    }
}

struct OstomyLogWidget: Widget {
    let kind = "OstomyLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            OstomyLogWidgetView(entry: entry)
        }
        .configurationDisplayName(AppConfig.appName)
        .description("Today's output and how long the barrier has been on.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct OstomyLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        OstomyLogWidget()
    }
}
