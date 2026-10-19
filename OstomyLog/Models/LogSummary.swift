import Foundation

/// The arithmetic the app is allowed to do: adding up what the user typed in, and dividing it by
/// how many days it covers.
///
/// Every figure here is a statement about the user's own entries. Nothing in this file decides
/// whether a number is good, bad, high or low, and nothing recommends anything. Where the user
/// has entered a daily figure their own clinician gave them, the summary counts how many days
/// were above it and labels it as theirs.
struct LogSummary {
    let events: [OstomyEvent]
    let range: ClosedRange<Date>
    let calendar: Calendar

    init(events: [OstomyEvent], range: ClosedRange<Date>, calendar: Calendar = .current) {
        self.calendar = calendar
        self.range = range
        self.events = events.filter { range.contains($0.date) }.sorted { $0.date < $1.date }
    }

    /// The last `days` calendar days, ending at the end of the day containing `now`.
    static func recent(_ events: [OstomyEvent], days: Int, asOf now: Date = .now,
                       calendar: Calendar = .current) -> LogSummary {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))
            ?? now
        return LogSummary(events: events, range: start...endOfToday, calendar: calendar)
    }

    // MARK: Slices

    func events(of kind: EventKind) -> [OstomyEvent] { events.filter { $0.kind == kind } }

    var emptyings: [OstomyEvent] { events(of: .emptying) }
    var changes: [OstomyEvent] { events(of: .applianceChange) }
    var leaks: [OstomyEvent] { events(of: .leak) }
    var skinChecks: [OstomyEvent] { events(of: .skinCheck) }

    /// Barrier changes only. A pouch swap on a two-piece is not a wear-time event.
    var barrierChanges: [OstomyEvent] { changes.filter(\.resetsWearTime) }

    // MARK: Output

    var totalOutputML: Double { emptyings.reduce(0) { $0 + $1.volumeML } }

    /// Days that actually have an emptying on them. Dividing by the calendar length of the period
    /// instead would quietly punish somebody for the days they did not open the app, and hand the
    /// nurse a number that is too low.
    var daysWithOutput: Int { Set(emptyings.map(\.day)).count }

    var averageDailyOutputML: Double? {
        guard daysWithOutput > 0 else { return nil }
        return totalOutputML / Double(daysWithOutput)
    }

    var averageEmptyingsPerDay: Double? {
        guard daysWithOutput > 0 else { return nil }
        return Double(emptyings.count) / Double(daysWithOutput)
    }

    var averageVolumePerEmptyingML: Double? {
        guard !emptyings.isEmpty else { return nil }
        return totalOutputML / Double(emptyings.count)
    }

    // MARK: Wear time

    /// Wear times recorded on the barrier changes in this period, in hours. A change with no
    /// earlier barrier change to measure from carries zero and is left out.
    var measuredWearHours: [Double] { barrierChanges.map(\.wearHours).filter { $0 > 0 } }

    var averageWearHours: Double? {
        guard !measuredWearHours.isEmpty else { return nil }
        return measuredWearHours.reduce(0, +) / Double(measuredWearHours.count)
    }

    var shortestWearHours: Double? { measuredWearHours.min() }
    var longestWearHours: Double? { measuredWearHours.max() }

    // MARK: Planned against forced

    var plannedChanges: Int { changes.filter { !$0.reason.wasForced }.count }
    var forcedChanges: Int { changes.filter { $0.reason.wasForced }.count }
    var leakForcedChanges: Int { changes.filter { $0.reason == .leak }.count }

    /// The share of changes that something forced, 0 to 1, or nil when nothing was changed.
    var forcedShare: Double? {
        guard !changes.isEmpty else { return nil }
        return Double(forcedChanges) / Double(changes.count)
    }

    // MARK: The user's own target

    /// How many recorded days went over the figure the user's own clinician gave them, and how
    /// many days were counted. Nil when they have not entered one. The app states the count; it
    /// does not say what it means.
    func daysOverTarget(_ targetML: Double?) -> (over: Int, counted: Int)? {
        guard let targetML, targetML > 0 else { return nil }
        let days = dailyTotals
        guard !days.isEmpty else { return nil }
        return (days.filter { $0.outputML > targetML }.count, days.count)
    }

    // MARK: Days

    struct Day: Identifiable, Equatable {
        let date: Date
        var outputML: Double = 0
        var emptyings: Int = 0
        var barrierChanges: Int = 0
        var pouchChanges: Int = 0
        var leaks: Int = 0
        var skinNote: String = ""

        var id: Date { date }
        var changes: Int { barrierChanges + pouchChanges }
    }

    /// One row per day that has at least one emptying, oldest first. Days with only a leak or a
    /// skin note are not output days and would drag an average down if they were counted.
    var dailyTotals: [Day] {
        var byDay: [Date: Day] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            var row = byDay[day] ?? Day(date: day)
            switch event.kind {
            case .emptying:
                row.outputML += event.volumeML
                row.emptyings += 1
            case .applianceChange:
                if event.resetsWearTime { row.barrierChanges += 1 } else { row.pouchChanges += 1 }
            case .leak:
                row.leaks += 1
            case .skinCheck:
                if let skin = event.skin { row.skinNote = skin.name }
            }
            byDay[day] = row
        }
        return byDay.values.filter { $0.emptyings > 0 }.sorted { $0.date < $1.date }
    }

    /// Every day in the period that has anything at all on it, for the history list.
    var allDays: [Day] {
        var byDay: [Date: Day] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            var row = byDay[day] ?? Day(date: day)
            switch event.kind {
            case .emptying: row.outputML += event.volumeML; row.emptyings += 1
            case .applianceChange: if event.resetsWearTime { row.barrierChanges += 1 } else { row.pouchChanges += 1 }
            case .leak: row.leaks += 1
            case .skinCheck: if let skin = event.skin { row.skinNote = skin.name }
            }
            byDay[day] = row
        }
        return byDay.values.sorted { $0.date > $1.date }
    }

    var isEmpty: Bool { events.isEmpty }
}

/// The two live numbers the home screen is built around, worked out over the whole log rather
/// than a reporting period.
enum WearClock {
    /// The barrier change currently on the skin: the most recent change that took the barrier off.
    static func currentBarrierChange(in events: [OstomyEvent], asOf now: Date = .now) -> OstomyEvent? {
        events.filter { $0.resetsWearTime && $0.date <= now }.max { $0.date < $1.date }
    }

    /// Hours the barrier on the skin has been on, or nil when no barrier change has ever been
    /// logged — in which case the app says so instead of showing a zero that looks like a fact.
    static func hoursOn(in events: [OstomyEvent], asOf now: Date = .now) -> Double? {
        guard let change = currentBarrierChange(in: events, asOf: now) else { return nil }
        return max(0, now.timeIntervalSince(change.date) / 3600)
    }

    /// The wear time to stamp on a change being saved now: hours since the barrier change before
    /// it. Zero when this is the first barrier change in the log, which the app prints as
    /// "first recorded change" rather than as a wear time of nothing.
    static func wearHours(forChangeAt date: Date, scope: ChangeScope,
                          in events: [OstomyEvent], excluding excluded: OstomyEvent? = nil) -> Double {
        guard scope.includesBarrier else { return 0 }
        let previous = events
            .filter { $0.resetsWearTime && $0.date < date && $0.id != excluded?.id }
            .max { $0.date < $1.date }
        guard let previous else { return 0 }
        return max(0, date.timeIntervalSince(previous.date) / 3600)
    }

    /// Output recorded on the calendar day containing `now`.
    static func outputToday(in events: [OstomyEvent], asOf now: Date = .now,
                            calendar: Calendar = .current) -> (millilitres: Double, emptyings: Int) {
        let today = calendar.startOfDay(for: now)
        let todays = events.filter { $0.kind == .emptying && calendar.startOfDay(for: $0.date) == today }
        return (todays.reduce(0) { $0 + $1.volumeML }, todays.count)
    }
}
