import Foundation

/// A tiny summary the app writes to the shared App Group so the widget can render
/// without touching SwiftData. The app updates it whenever a record changes.
///
/// The two numbers on the widget are the two the home screen leads with: what has come out
/// today, and how long the barrier has been on.
struct WidgetSnapshot: Codable {
    var outputTodayML: Double = 0
    var emptyingsToday: Int = 0
    /// When the barrier currently on the skin went on. Nil until the first barrier change is logged.
    var lastBarrierChange: Date?
    /// Average barrier wear time over the recent history, in hours. Zero when there is not enough history.
    var averageWearHours: Double = 0
    var daysOfSuppliesLeft: Int?
    var updatedAt: Date = .now

    static let storageKey = "widget.snapshot"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    static func load() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot()
        }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults.set(data, forKey: Self.storageKey)
    }

    /// Hours the barrier has been on as of `now`, or nil when no barrier change has been logged.
    func wearHours(asOf now: Date = .now) -> Double? {
        guard let lastBarrierChange else { return nil }
        return max(0, now.timeIntervalSince(lastBarrierChange) / 3600)
    }

    static let placeholder = WidgetSnapshot(
        outputTodayML: 780, emptyingsToday: 4,
        lastBarrierChange: Calendar.current.date(byAdding: .hour, value: -52, to: .now),
        averageWearHours: 76, daysOfSuppliesLeft: 11)
}

/// "2 days 4 hr", "18 hr", "45 min". Long units, whole words, never an abbreviation the reader
/// has to decode.
enum WearTimeFormat {
    static func short(hours: Double) -> String {
        guard hours >= 1 else { return "\(Int((hours * 60).rounded())) min" }
        if hours < 48 { return "\(Int(hours.rounded(.down))) hr" }
        let days = Int(hours / 24)
        let remainder = Int(hours.truncatingRemainder(dividingBy: 24))
        return remainder == 0 ? "\(days) days" : "\(days) days \(remainder) hr"
    }

    /// "3.2 days", the way a wear-time average is quoted at an appointment.
    static func days(hours: Double) -> String {
        String(format: "%.1f days", hours / 24)
    }
}
