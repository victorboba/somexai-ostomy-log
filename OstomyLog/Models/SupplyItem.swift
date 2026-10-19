import Foundation
import SwiftData

/// One thing the user keeps in the cupboard, named in their own words.
///
/// Deliberately free text. The manufacturer apps exist to reorder that manufacturer's catalogue,
/// which is why they are free and why they are no use to somebody who wears a barrier from one
/// company and a belt from another. This app never knows or cares what brand it is.
///
/// The countdown is arithmetic on the user's own history: how many of these an appliance change
/// uses, against how often they have actually been changing. It is not a recommendation to order,
/// and it never says how often anybody should change.
@Model
final class SupplyItem {
    var id: UUID = UUID()
    var name: String = ""
    /// Size or cut, as written on the box: "45 mm", "cut-to-fit 20-45 mm", "large drainable".
    var size: String = ""
    var quantityOnHand: Int = 0
    /// How many of this item one event uses. A barrier is one per barrier change; a box of wipes
    /// might be two.
    var quantityPerUse: Int = 1
    var basisRaw: String = SupplyBasis.barrierChange.rawValue
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String = "", size: String = "", quantityOnHand: Int = 0,
         quantityPerUse: Int = 1, basis: SupplyBasis = .barrierChange) {
        self.id = UUID()
        self.name = name
        self.size = size
        self.quantityOnHand = quantityOnHand
        self.quantityPerUse = quantityPerUse
        self.basisRaw = basis.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }

    var basis: SupplyBasis {
        get { SupplyBasis(rawValue: basisRaw) ?? .barrierChange }
        set { basisRaw = newValue.rawValue }
    }

    var title: String {
        size.isEmpty ? name : "\(name) · \(size)"
    }

    /// Whole days of this item left at the user's own observed rate, or nil when there is not
    /// enough history to work one out. Nil is an honest answer and is shown as one.
    func daysRemaining(rates: UsageRates) -> Int? {
        guard quantityOnHand > 0, quantityPerUse > 0 else { return quantityOnHand <= 0 ? 0 : nil }
        guard let perDay = rates.perDay(for: basis), perDay > 0 else { return nil }
        let usedPerDay = perDay * Double(quantityPerUse)
        return Int((Double(quantityOnHand) / usedPerDay).rounded(.down))
    }
}

enum SupplyBasis: String, CaseIterable, Identifiable, Sendable {
    case barrierChange, pouchChange, day

    var id: String { rawValue }

    var name: String {
        switch self {
        case .barrierChange: return "Each barrier change"
        case .pouchChange: return "Each pouch change"
        case .day: return "Each day"
        }
    }
}

/// How often the three consuming events have actually been happening, per day, measured from the
/// user's own log rather than assumed.
struct UsageRates: Equatable, Sendable {
    var barrierChangesPerDay: Double = 0
    var pouchChangesPerDay: Double = 0
    /// Always one; kept here so `perDay(for:)` has one shape.
    var daysPerDay: Double = 1

    func perDay(for basis: SupplyBasis) -> Double? {
        switch basis {
        case .barrierChange: return barrierChangesPerDay > 0 ? barrierChangesPerDay : nil
        case .pouchChange: return pouchChangesPerDay > 0 ? pouchChangesPerDay : nil
        case .day: return daysPerDay
        }
    }

    /// Counts the changes in `events` and spreads them over the observed window.
    ///
    /// The window is the span the log actually covers, capped at `windowDays`, because dividing
    /// three changes by thirty days on somebody's second day with the app produces a countdown
    /// that is wrong by a factor of ten.
    static func measured(from events: [OstomyEvent], windowDays: Int = 30,
                         asOf now: Date = .now, calendar: Calendar = .current) -> UsageRates {
        let changes = events.filter { $0.kind == .applianceChange && $0.date <= now }
        guard let earliest = changes.map(\.date).min(), changes.count >= 2 else { return UsageRates() }

        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? earliest
        let start = max(earliest, windowStart)
        let inWindow = changes.filter { $0.date >= start }
        guard inWindow.count >= 2 else { return UsageRates() }

        let span = now.timeIntervalSince(start) / 86400
        guard span > 0 else { return UsageRates() }

        let barrier = inWindow.filter(\.resetsWearTime).count
        let pouch = inWindow.filter { $0.scope != .barrierOnly }.count
        return UsageRates(barrierChangesPerDay: Double(barrier) / span,
                          pouchChangesPerDay: Double(pouch) / span)
    }
}
