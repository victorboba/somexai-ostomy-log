import Foundation
import SwiftData

#if DEBUG
/// Debug-only sample data for screenshots and manual testing: five weeks of a fairly typical
/// ileostomy, with a barrier lasting about three days, two changes forced by a leak, and a stretch
/// of sore skin that settles down again.
///
/// Launch with `-sampleData` to insert it on first run, or use Settings → Debug → Insert sample data.
enum SampleData {
    static func insert(into context: ModelContext) {
        StomaProfile.stomaType = .ileostomy
        StomaProfile.applianceSystem = .twoPiece
        StomaProfile.volumeUnit = .millilitres
        StomaProfile.dailyOutputTargetML = 1200

        let calendar = Calendar.current
        var generator = SystemRandomNumberGenerator()
        var events: [OstomyEvent] = []

        // Emptyings: five to seven a day, bigger in the morning, smaller overnight.
        for offset in stride(from: 34, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
            let hours = [7, 11, 14, 17, 20, 23, 3].prefix(Int.random(in: 5...7, using: &generator))
            for hour in hours {
                guard let time = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...59, using: &generator),
                                               second: 0, of: day), time <= .now else { continue }
                let event = OstomyEvent(kind: .emptying, date: time)
                event.volumeML = Double(Int.random(in: hour <= 8 ? 180...320 : 90...260, using: &generator))
                event.character = hour == 3 ? .watery : [OutputCharacter.porridge, .thin, .thick].randomElement(using: &generator)
                events.append(event)
            }
        }

        // Appliance changes: a barrier about every three days, with two forced by a leak and one
        // day where only the pouch was swapped — which does not restart the wear clock.
        var lastBarrier: Date?
        for offset in stride(from: 33, through: 0, by: -3) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now),
                  let time = calendar.date(bySettingHour: 8, minute: 15, second: 0, of: day), time <= .now
            else { continue }
            let change = OstomyEvent(kind: .applianceChange, date: time)
            change.scope = .barrierAndPouch
            change.reason = (offset == 21 || offset == 6) ? .leak : .planned
            change.wearHours = lastBarrier.map { max(0, time.timeIntervalSince($0) / 3600) } ?? 0
            lastBarrier = time
            events.append(change)

            if offset == 15, let pouchOnly = calendar.date(byAdding: .hour, value: 30, to: time) {
                let swap = OstomyEvent(kind: .applianceChange, date: pouchOnly)
                swap.scope = .pouchOnly
                swap.reason = .planned
                swap.notes = "Pouch swapped, barrier left on."
                events.append(swap)
            }
        }

        // Leaks, the thing the log exists to make visible.
        for (offset, cause, note) in [(21, LeakCause.sweat, "Hot day, seal lifted at the bottom edge."),
                                      (6, LeakCause.output, "Very liquid overnight, woke up to a leak.")] {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now),
                  let time = calendar.date(bySettingHour: 7, minute: 40, second: 0, of: day) else { continue }
            let leak = OstomyEvent(kind: .leak, date: time)
            leak.leakCause = cause
            leak.notes = note
            events.append(leak)
        }

        // Skin checks, in the user's own words.
        for (offset, condition, note) in [(28, SkinCondition.intact, ""),
                                          (20, SkinCondition.red, "Sore on the lower edge after the leak."),
                                          (13, SkinCondition.pink, "Much better with a smaller cut."),
                                          (5, SkinCondition.sore, "Weeping a little where it leaked."),
                                          (1, SkinCondition.pink, "Settling again.")] {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now),
                  let time = calendar.date(bySettingHour: 8, minute: 45, second: 0, of: day) else { continue }
            let check = OstomyEvent(kind: .skinCheck, date: time)
            check.skin = condition
            check.notes = note
            events.append(check)
        }

        for event in events { context.insert(event) }

        for supply in [SupplyItem(name: "Barrier", size: "cut-to-fit 20 to 45 mm", quantityOnHand: 9,
                                  quantityPerUse: 1, basis: .barrierChange),
                       SupplyItem(name: "Drainable pouch", size: "large, beige", quantityOnHand: 22,
                                  quantityPerUse: 1, basis: .pouchChange),
                       SupplyItem(name: "Barrier ring", size: "2 mm", quantityOnHand: 4,
                                  quantityPerUse: 1, basis: .barrierChange),
                       SupplyItem(name: "Adhesive remover wipe", size: "box of 30", quantityOnHand: 26,
                                  quantityPerUse: 2, basis: .barrierChange)] {
            context.insert(supply)
        }

        try? context.save()
    }
}
#endif
