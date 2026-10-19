import Foundation
import WidgetKit

enum WidgetSync {
    /// The summary the widget renders. Pure, so it can be tested without touching UserDefaults.
    static func snapshot(events: [OstomyEvent], supplies: [SupplyItem],
                         asOf now: Date = .now) -> WidgetSnapshot {
        var snapshot = WidgetSnapshot()
        let today = WearClock.outputToday(in: events, asOf: now)
        snapshot.outputTodayML = today.millilitres
        snapshot.emptyingsToday = today.emptyings
        snapshot.lastBarrierChange = WearClock.currentBarrierChange(in: events, asOf: now)?.date
        snapshot.averageWearHours = LogSummary.recent(events, days: 30, asOf: now).averageWearHours ?? 0
        let rates = UsageRates.measured(from: events, asOf: now)
        snapshot.daysOfSuppliesLeft = supplies.compactMap { $0.daysRemaining(rates: rates) }.min()
        snapshot.updatedAt = now
        return snapshot
    }

    /// Recomputes the widget summary and reloads timelines.
    static func update(events: [OstomyEvent], supplies: [SupplyItem]) {
        snapshot(events: events, supplies: supplies).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
