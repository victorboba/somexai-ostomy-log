import Testing
import Foundation
import PDFKit
@testable import OstomyLog

// MARK: - Helpers

private let calendar = Calendar(identifier: .gregorian)

private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 6
    components.day = day
    components.hour = hour
    components.minute = minute
    components.timeZone = TimeZone(identifier: "UTC")
    return calendar.date(from: components)!
}

private func emptying(_ when: Date, _ ml: Double, _ character: OutputCharacter? = nil) -> OstomyEvent {
    let event = OstomyEvent(kind: .emptying, date: when)
    event.volumeML = ml
    event.character = character
    return event
}

private func change(_ when: Date, scope: ChangeScope = .whole, reason: ChangeReason = .planned,
                    wearHours: Double = 0) -> OstomyEvent {
    let event = OstomyEvent(kind: .applianceChange, date: when)
    event.scope = scope
    event.reason = reason
    event.wearHours = wearHours
    return event
}

private func leak(_ when: Date, _ cause: LeakCause = .notSure) -> OstomyEvent {
    let event = OstomyEvent(kind: .leak, date: when)
    event.leakCause = cause
    return event
}

private func skinCheck(_ when: Date, _ condition: SkinCondition) -> OstomyEvent {
    let event = OstomyEvent(kind: .skinCheck, date: when)
    event.skin = condition
    return event
}

private var utcCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

// MARK: - Volume

/// Millilitres are stored; ounces are a display choice. Getting this wrong hands a nurse a number
/// that is out by a factor of thirty.
struct VolumeTests {
    @Test func millilitresConvertToFluidOunces() {
        #expect(abs(Volume.fluidOunces(fromMillilitres: 29.5735295625) - 1) < 0.0001)
        #expect(abs(Volume.fluidOunces(fromMillilitres: 1000) - 33.814) < 0.001)
    }

    @Test func theConversionRoundTrips() {
        let ml = Volume.millilitres(fromFluidOunces: Volume.fluidOunces(fromMillilitres: 237))
        #expect(abs(ml - 237) < 0.0001)
    }

    @Test func millilitresPrintAsWholeNumbers() {
        #expect(Volume.format(millilitres: 249.6, in: .millilitres) == "250 ml")
        #expect(Volume.format(millilitres: 0, in: .millilitres) == "0 ml")
    }

    @Test func ouncesKeepOneDecimalBecauseRoundingLosesTooMuch() {
        #expect(Volume.format(millilitres: 250, in: .fluidOunces) == "8.5 fl oz")
    }

    @Test func theReportShowsBothUnitsWithThousandsGrouped() {
        let text = Volume.formatBoth(millilitres: 1450)
        #expect(text.contains("1,450 ml"))
        #expect(text.contains("49.0 fl oz"))
    }
}

// MARK: - Wear time, the number the app exists to produce

struct WearTimeTests {
    @Test func aBarrierChangeMeasuresFromThePreviousBarrierChange() {
        let events = [change(date(1, 8)), change(date(4, 8))]
        let hours = WearClock.wearHours(forChangeAt: date(4, 8), scope: .whole, in: events,
                                        excluding: events[1])
        #expect(hours == 72)
    }

    @Test func theFirstChangeInTheLogHasNoWearTimeToMeasure() {
        let events = [change(date(1, 8))]
        #expect(WearClock.wearHours(forChangeAt: date(1, 8), scope: .whole, in: events, excluding: events[0]) == 0)
    }

    /// The rule the whole app turns on: a pouch swap leaves the barrier on the skin.
    @Test func swappingOnlyThePouchDoesNotRestartTheClock() {
        let events = [change(date(1, 8), scope: .barrierAndPouch),
                      change(date(2, 8), scope: .pouchOnly),
                      change(date(4, 8), scope: .barrierAndPouch)]
        let hours = WearClock.wearHours(forChangeAt: date(4, 8), scope: .barrierAndPouch,
                                        in: events, excluding: events[2])
        #expect(hours == 72, "the pouch swap on day 2 must not shorten the barrier's wear time")
    }

    @Test func aPouchOnlyChangeIsItselfNeverGivenAWearTime() {
        let events = [change(date(1, 8), scope: .barrierAndPouch)]
        #expect(WearClock.wearHours(forChangeAt: date(3, 8), scope: .pouchOnly, in: events) == 0)
    }

    @Test func theClockOnTheHomeScreenCountsFromTheBarrierCurrentlyWorn() {
        let events = [change(date(1, 8), scope: .barrierAndPouch),
                      change(date(3, 8), scope: .pouchOnly)]
        let hours = WearClock.hoursOn(in: events, asOf: date(3, 20))
        #expect(hours == 60, "60 hours since the barrier went on, not 12 since the pouch")
    }

    @Test func withNoChangeAtAllTheClockIsNilRatherThanZero() {
        #expect(WearClock.hoursOn(in: [emptying(date(1), 200)], asOf: date(2)) == nil)
    }

    @Test func aFutureChangeIsNotTheBarrierCurrentlyWorn() {
        let events = [change(date(1, 8)), change(date(9, 8))]
        #expect(WearClock.currentBarrierChange(in: events, asOf: date(4))?.date == date(1, 8))
    }

    @Test func wearTimeReadsInLongUnits() {
        #expect(WearTimeFormat.short(hours: 0.5) == "30 min")
        #expect(WearTimeFormat.short(hours: 18.4) == "18 hr")
        #expect(WearTimeFormat.short(hours: 72) == "3 days")
        #expect(WearTimeFormat.short(hours: 76) == "3 days 4 hr")
        #expect(WearTimeFormat.days(hours: 76.8) == "3.2 days")
    }
}

// MARK: - What the app asks, and of whom

struct QuestionApplicabilityTests {
    @Test func aUrostomyIsNeverAskedAboutStoolConsistency() {
        let options = OutputCharacter.options(for: .urostomy)
        #expect(!options.contains(.porridge))
        #expect(options.contains(.cloudy))
    }

    @Test func anIleostomyIsNeverAskedWhetherTheOutputWasCloudy() {
        let options = OutputCharacter.options(for: .ileostomy)
        #expect(options.contains(.porridge))
        #expect(!options.contains(.cloudy))
        #expect(options == OutputCharacter.options(for: .colostomy))
    }

    @Test func aOnePieceApplianceHasOnlyOneKindOfChange() {
        #expect(ApplianceSystem.onePiece.changeScopes == [.whole])
        #expect(ApplianceSystem.twoPiece.changeScopes.contains(.pouchOnly))
    }

    @Test func everyScopeExceptAPouchSwapTakesTheBarrierOff() {
        #expect(ChangeScope.whole.includesBarrier)
        #expect(ChangeScope.barrierAndPouch.includesBarrier)
        #expect(ChangeScope.barrierOnly.includesBarrier)
        #expect(!ChangeScope.pouchOnly.includesBarrier)
    }

    @Test func everyChangeReasonExceptPlannedCountsAsForced() {
        #expect(!ChangeReason.planned.wasForced)
        for reason in ChangeReason.allCases where reason != .planned {
            #expect(reason.wasForced, "\(reason.name) is not a planned change")
        }
    }
}

// MARK: - The summary

struct SummaryTests {
    private func week() -> [OstomyEvent] {
        [emptying(date(1, 8), 200), emptying(date(1, 13), 150), emptying(date(1, 20), 250),
         emptying(date(2, 9), 300), emptying(date(2, 21), 100),
         change(date(1, 7), reason: .planned),
         change(date(4, 7), reason: .leak, wearHours: 72),
         leak(date(4, 6), .sweat),
         skinCheck(date(4, 8), .red)]
    }

    private func summary(_ events: [OstomyEvent]) -> LogSummary {
        LogSummary(events: events, range: date(1, 0)...date(8, 0), calendar: utcCalendar)
    }

    @Test func totalsAddUpOnlyTheEmptyings() {
        #expect(summary(week()).totalOutputML == 1000)
        #expect(summary(week()).emptyings.count == 5)
    }

    @Test func theDailyAverageDividesByDaysThatHaveARecordNotByTheCalendar() {
        let s = summary(week())
        #expect(s.daysWithOutput == 2)
        #expect(s.averageDailyOutputML == 500)
        #expect(s.averageEmptyingsPerDay == 2.5)
        #expect(s.averageVolumePerEmptyingML == 200)
    }

    @Test func anEmptyPeriodAveragesNothingRatherThanZero() {
        let s = summary([])
        #expect(s.isEmpty)
        #expect(s.averageDailyOutputML == nil)
        #expect(s.averageWearHours == nil)
        #expect(s.forcedShare == nil)
        #expect(s.dailyTotals.isEmpty)
    }

    @Test func aSingleEmptyingIsItsOwnAverage() {
        let s = summary([emptying(date(2, 9), 175)])
        #expect(s.averageDailyOutputML == 175)
        #expect(s.averageEmptyingsPerDay == 1)
        #expect(s.dailyTotals.count == 1)
    }

    @Test func anEmptyingOfZeroStillCountsAsAnEmptying() {
        let s = summary([emptying(date(2, 9), 0)])
        #expect(s.emptyings.count == 1)
        #expect(s.averageDailyOutputML == 0)
        #expect(s.daysWithOutput == 1)
    }

    @Test func onlyMeasuredWearTimesGoIntoTheAverage() {
        let s = summary(week())
        #expect(s.measuredWearHours == [72], "the first change has nothing to measure from")
        #expect(s.averageWearHours == 72)
        #expect(s.shortestWearHours == 72)
        #expect(s.longestWearHours == 72)
    }

    @Test func plannedAgainstForcedIsCountedSeparatelyFromLeaks() {
        let s = summary(week())
        #expect(s.plannedChanges == 1)
        #expect(s.forcedChanges == 1)
        #expect(s.leakForcedChanges == 1)
        #expect(s.forcedShare == 0.5)
    }

    @Test func daysWithoutAnEmptyingDoNotAppearInTheDailyTable() {
        // Day 4 has a leak and a skin check but no emptying, so it is not an output day.
        let rows = summary(week()).dailyTotals
        #expect(rows.count == 2)
        #expect(rows.first?.outputML == 600)
        #expect(rows.first?.emptyings == 3)
        #expect(!rows.contains { $0.date == utcCalendar.startOfDay(for: date(4)) })
    }

    @Test func theHistoryListShowsEveryDayThatHasAnythingOnIt() {
        let days = summary(week()).allDays
        #expect(days.count == 3, "day 4 has a leak and a skin check and still belongs in the history")
        #expect(days.first?.leaks == 1)
        #expect(days.first?.skinNote == "Red")
    }

    @Test func aPouchSwapIsCountedAsAChangeButNotAsABarrierChange() {
        let events = [emptying(date(1, 9), 100),
                      change(date(1, 8), scope: .pouchOnly),
                      change(date(1, 10), scope: .barrierAndPouch, wearHours: 50)]
        let s = summary(events)
        #expect(s.changes.count == 2)
        #expect(s.barrierChanges.count == 1)
        #expect(s.dailyTotals.first?.changes == 2)
        #expect(s.dailyTotals.first?.barrierChanges == 1)
    }

    @Test func eventsOutsideTheRangeAreLeftOut() {
        let s = summary([emptying(date(1, 9), 100), emptying(date(30, 9), 900)])
        #expect(s.totalOutputML == 100)
    }

    @Test func theRecentWindowCoversTheWholeOfTheFirstDay() {
        let events = [emptying(date(1, 0, 5), 100), emptying(date(7, 23, 55), 200)]
        let s = LogSummary.recent(events, days: 7, asOf: date(7, 12), calendar: utcCalendar)
        #expect(s.totalOutputML == 300)
    }
}

// MARK: - The user's own target

/// The app stores a figure the user was given. It never invents one, and it never says what
/// being over it means.
struct TargetTests {
    private func summary(_ events: [OstomyEvent]) -> LogSummary {
        LogSummary(events: events, range: date(1, 0)...date(8, 0), calendar: utcCalendar)
    }

    @Test func withNoTargetThereIsNothingToReport() {
        #expect(summary([emptying(date(1, 9), 1500)]).daysOverTarget(nil) == nil)
        #expect(summary([emptying(date(1, 9), 1500)]).daysOverTarget(0) == nil)
    }

    @Test func daysAboveTheUsersOwnFigureAreCounted() {
        let events = [emptying(date(1, 9), 700), emptying(date(1, 15), 700),
                      emptying(date(2, 9), 500)]
        let result = summary(events).daysOverTarget(1200)
        #expect(result?.over == 1)
        #expect(result?.counted == 2)
    }

    @Test func aDayExactlyOnTheFigureIsNotAboveIt() {
        let result = summary([emptying(date(1, 9), 1200)]).daysOverTarget(1200)
        #expect(result?.over == 0)
    }

    @Test func aTargetWithNoDaysRecordedReportsNothing() {
        #expect(summary([]).daysOverTarget(1200) == nil)
    }
}

// MARK: - Supplies

struct SupplyTests {
    private func changesEveryThreeDays() -> [OstomyEvent] {
        [change(date(1, 8)), change(date(4, 8)), change(date(7, 8)), change(date(10, 8))]
    }

    @Test func theRateComesFromTheUsersOwnChanges() {
        let rates = UsageRates.measured(from: changesEveryThreeDays(), asOf: date(10, 8),
                                        calendar: utcCalendar)
        // Four changes over the nine days between the first and the last.
        #expect(abs(rates.barrierChangesPerDay - 4.0 / 9.0) < 0.0001)
    }

    @Test func oneChangeIsNotARate() {
        let rates = UsageRates.measured(from: [change(date(1, 8))], asOf: date(4), calendar: utcCalendar)
        #expect(rates.barrierChangesPerDay == 0)
        #expect(rates.perDay(for: .barrierChange) == nil)
    }

    @Test func aPouchSwapCountsTowardPouchesAndNotBarriers() {
        let events = [change(date(1, 8), scope: .barrierAndPouch),
                      change(date(2, 8), scope: .pouchOnly),
                      change(date(4, 8), scope: .barrierAndPouch)]
        let rates = UsageRates.measured(from: events, asOf: date(4, 8), calendar: utcCalendar)
        #expect(rates.barrierChangesPerDay < rates.pouchChangesPerDay)
    }

    @Test func theCountdownDividesWhatIsLeftByTheObservedRate() {
        let rates = UsageRates(barrierChangesPerDay: 1.0 / 3.0, pouchChangesPerDay: 0.5)
        let barriers = SupplyItem(name: "Barrier", quantityOnHand: 9, quantityPerUse: 1, basis: .barrierChange)
        #expect(barriers.daysRemaining(rates: rates) == 27)
    }

    @Test func twoOfSomethingPerChangeLastsHalfAsLong() {
        let rates = UsageRates(barrierChangesPerDay: 1.0 / 3.0)
        let wipes = SupplyItem(name: "Wipes", quantityOnHand: 10, quantityPerUse: 2, basis: .barrierChange)
        #expect(wipes.daysRemaining(rates: rates) == 15)
    }

    @Test func anItemUsedEveryDayNeedsNoChangeHistory() {
        let item = SupplyItem(name: "Barrier spray", quantityOnHand: 12, quantityPerUse: 1, basis: .day)
        #expect(item.daysRemaining(rates: UsageRates()) == 12)
    }

    @Test func noneLeftIsZeroDaysAndNotAnUnknown() {
        let item = SupplyItem(name: "Barrier", quantityOnHand: 0, basis: .barrierChange)
        #expect(item.daysRemaining(rates: UsageRates(barrierChangesPerDay: 0.5)) == 0)
    }

    @Test func withoutARateTheCountdownSaysSoRatherThanGuessing() {
        let item = SupplyItem(name: "Barrier", quantityOnHand: 9, basis: .barrierChange)
        #expect(item.daysRemaining(rates: UsageRates()) == nil)
    }

    @Test func anItemUsedZeroTimesPerChangeNeverDividesByZero() {
        let item = SupplyItem(name: "Odd", quantityOnHand: 5, quantityPerUse: 0, basis: .barrierChange)
        #expect(item.daysRemaining(rates: UsageRates(barrierChangesPerDay: 0.5)) == nil)
    }
}

// MARK: - The widget summary

struct WidgetSnapshotTests {
    @Test func theSnapshotCarriesTodaysOutputAndTheWornBarrier() {
        var calendarUTC = utcCalendar
        calendarUTC.timeZone = .current
        let now = Date.now
        let earlier = now.addingTimeInterval(-3600)
        let events = [emptying(now.addingTimeInterval(-600), 250),
                      emptying(earlier, 150),
                      change(now.addingTimeInterval(-86_400 * 2), wearHours: 0)]
        let snapshot = WidgetSync.snapshot(events: events, supplies: [], asOf: now)
        #expect(snapshot.outputTodayML >= 250)
        #expect(snapshot.emptyingsToday >= 1)
        #expect(abs((snapshot.wearHours(asOf: now) ?? 0) - 48) < 0.1)
    }

    @Test func yesterdaysOutputIsNotTodays() {
        let now = Date.now
        let events = [emptying(now.addingTimeInterval(-86_400 * 2), 900)]
        let snapshot = WidgetSync.snapshot(events: events, supplies: [], asOf: now)
        #expect(snapshot.outputTodayML == 0)
        #expect(snapshot.emptyingsToday == 0)
    }

    @Test func withNoChangeLoggedTheWidgetHasNoWearTime() {
        let snapshot = WidgetSync.snapshot(events: [], supplies: [], asOf: .now)
        #expect(snapshot.lastBarrierChange == nil)
        #expect(snapshot.wearHours() == nil)
        #expect(snapshot.daysOfSuppliesLeft == nil)
    }

    @Test func theSoonestSupplyIsTheOneTheWidgetShows() {
        let now = Date.now
        let events = [change(now.addingTimeInterval(-86_400 * 6)),
                      change(now.addingTimeInterval(-86_400 * 3)),
                      change(now)]
        let supplies = [SupplyItem(name: "Barrier", quantityOnHand: 9, basis: .barrierChange),
                        SupplyItem(name: "Ring", quantityOnHand: 2, basis: .barrierChange)]
        let snapshot = WidgetSync.snapshot(events: events, supplies: supplies, asOf: now)
        #expect(snapshot.daysOfSuppliesLeft != nil)
        #expect(snapshot.daysOfSuppliesLeft == supplies.map {
            $0.daysRemaining(rates: UsageRates.measured(from: events, asOf: now)) ?? .max
        }.min())
    }
}

// MARK: - CSV

struct CSVTests {
    @Test func theHeaderNamesEveryColumnThatIsWritten() {
        let columns = CSVExporter.header.split(separator: ",")
        #expect(columns.count == 13)
        #expect(CSVExporter.header.contains("wear_hours"))
        #expect(CSVExporter.header.contains("volume_floz"))
    }

    @Test func oneRowPerRecordPlusTheHeader() {
        let csv = CSVExporter.csv(for: [emptying(date(1, 9), 200), change(date(1, 8), wearHours: 70), leak(date(2))])
        #expect(csv.split(separator: "\n").count == 4)
    }

    @Test func anEmptyingCarriesBothUnitsAndNoChangeColumns() {
        let csv = CSVExporter.csv(for: [emptying(date(1, 9), 250, .porridge)])
        let row = csv.split(separator: "\n")[1]
        #expect(row.contains("\"250\""))
        #expect(row.contains("\"8.5\""))
        #expect(row.contains("\"Porridge\""))
        #expect(row.contains("\"Emptying\""))
    }

    @Test func aChangeCarriesItsWearTimeInHoursAndDays() {
        let csv = CSVExporter.csv(for: [change(date(4, 8), scope: .barrierAndPouch, reason: .leak, wearHours: 72)])
        #expect(csv.contains("\"72.0\""))
        #expect(csv.contains("\"3.00\""))
        #expect(csv.contains("\"Barrier and pouch\""))
        #expect(csv.contains("\"Leak\""))
    }

    @Test func aFirstChangeLeavesTheWearColumnsEmptyRatherThanWritingZero() {
        let csv = CSVExporter.csv(for: [change(date(1, 8), wearHours: 0)])
        let row = csv.split(separator: "\n")[1]
        #expect(!row.contains("\"0.0\""))
    }

    @Test func quotesInANoteAreEscaped() {
        let event = emptying(date(1, 9), 100)
        event.notes = "She said \"watch it\""
        #expect(CSVExporter.csv(for: [event]).contains("\"\"watch it\"\""))
    }

    @Test func rowsComeOutOldestFirst() {
        let csv = CSVExporter.csv(for: [emptying(date(5, 9), 500), emptying(date(1, 9), 100)])
        let rows = csv.split(separator: "\n")
        #expect(rows[1].contains("2026-06-01"))
        #expect(rows[2].contains("2026-06-05"))
    }

    @Test func aPhotoIsNotedButNeverExported() {
        let check = skinCheck(date(1), .red)
        check.photoData = Data([0x1, 0x2, 0x3])
        let csv = CSVExporter.csv(for: [check])
        #expect(csv.contains("\"on file\""))
        #expect(!csv.contains("\u{1}"))
    }
}

// MARK: - The appointment PDF
//
// Rule 7: PDFKit collapses and rewraps whitespace, so every phrase is normalised before it is
// matched and the pieces of a row are asserted separately, never their adjacency.

struct PDFTests {
    private func text(_ url: URL) throws -> String {
        let document = try #require(PDFDocument(url: url))
        let raw = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: " ")
        return raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func report() -> [OstomyEvent] {
        [emptying(date(1, 8), 300, .porridge), emptying(date(1, 14), 250), emptying(date(1, 22), 200),
         emptying(date(2, 9), 400), emptying(date(2, 20), 150),
         change(date(1, 7), reason: .planned),
         change(date(4, 7), scope: .barrierAndPouch, reason: .leak, wearHours: 72),
         leak(date(4, 6), .sweat),
         skinCheck(date(4, 8), .red)]
    }

    private func summary(_ events: [OstomyEvent]) -> LogSummary {
        LogSummary(events: events, range: date(1, 0)...date(8, 0), calendar: utcCalendar)
    }

    @Test func theReportLeadsWithTheThreeThingsTheNurseAsks() throws {
        let url = try PDFExporter.export(summary: summary(report()), asOf: date(8))
        let text = try text(url)
        #expect(text.contains("Ostomy diary"))
        #expect(text.contains("At a glance"))
        #expect(text.contains("Average daily output"))
        #expect(text.contains("Average wear time"))
        #expect(text.contains("Appliance changes"))
    }

    @Test func theFiguresThemselvesAreOnThePage() throws {
        let url = try PDFExporter.export(summary: summary(report()), asOf: date(8))
        let text = try text(url)
        // 1,500 ml over two days with a record.
        #expect(text.contains("750 ml"))
        #expect(text.contains("3.0 days"), "the one measured wear time is 72 hours")
        #expect(text.contains("2 in total, 1 planned, 1 after a leak"))
    }

    @Test func everyDayWithAnEmptyingHasARowAndTheOthersDoNot() throws {
        let url = try PDFExporter.export(summary: summary(report()), asOf: date(8))
        let text = try text(url)
        #expect(text.contains("Day by day"))
        #expect(text.contains("750 ml"))
        #expect(text.contains("550 ml"))
    }

    @Test func theLeakAndTheSkinNoteAreBothPrinted() throws {
        let url = try PDFExporter.export(summary: summary(report()), asOf: date(8))
        let text = try text(url)
        #expect(text.contains("Leaks"))
        #expect(text.contains("Sweat or heat"))
        #expect(text.contains("Skin around the stoma"))
        #expect(text.contains("Red"))
    }

    @Test func anEmptyPeriodProducesAnHonestPageRatherThanABlankOne() throws {
        let url = try PDFExporter.export(summary: summary([]), asOf: date(8))
        let text = try text(url)
        #expect(text.contains("No emptyings were recorded in this period."))
        #expect(text.contains("No appliance changes were recorded in this period."))
        #expect(text.contains("No leaks were recorded in this period."))
        #expect(text.contains("Not enough changes to measure"))
    }

    @Test func theReportSaysWhatItIsAndWhatItIsNot() throws {
        let url = try PDFExporter.export(summary: summary(report()), asOf: date(8))
        let text = try text(url)
        #expect(text.contains("is a diary"))
        #expect(text.contains("no clinical assessment"))
        #expect(text.contains("no advice"))
        #expect(!text.lowercased().contains("we recommend"))
        #expect(!text.lowercased().contains("too high"))
    }

    @Test func photographsAreNamedButNeverIncluded() throws {
        let events = report()
        let check = events.first { $0.kind == .skinCheck }
        check?.photoData = Data([0xFF, 0xD8, 0xFF])
        let url = try PDFExporter.export(summary: summary(events), asOf: date(8))
        let text = try text(url)
        #expect(text.contains("photo kept on the phone"))
    }

    @Test func suppliesAppearOnlyWhenThereAreAny() throws {
        let plain = try text(try PDFExporter.export(summary: summary(report()), asOf: date(8)))
        #expect(!plain.contains("Supplies on hand"))

        let withSupplies = try text(try PDFExporter.export(
            summary: summary(report()),
            supplies: [SupplyItem(name: "Barrier", size: "45 mm", quantityOnHand: 9, basis: .barrierChange)],
            rates: UsageRates(barrierChangesPerDay: 1.0 / 3.0), asOf: date(8)))
        #expect(withSupplies.contains("Supplies on hand"))
        #expect(withSupplies.contains("Barrier"))
    }

    @Test func aLongLogPaginatesInsteadOfRunningOffThePage() throws {
        var events: [OstomyEvent] = []
        for day in 1...28 {
            for hour in [8, 12, 16, 20, 23] {
                events.append(emptying(date(day, hour), 180))
            }
            if day % 3 == 0 { events.append(change(date(day, 7), wearHours: 72)) }
        }
        let summary = LogSummary(events: events, range: date(1, 0)...date(29, 0), calendar: utcCalendar)
        let url = try PDFExporter.export(summary: summary, asOf: date(29))
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount >= 2)
    }
}

// MARK: - The record itself

struct EventTests {
    @Test func everyKindHasItsOwnHeadlineAndSymbol() {
        #expect(EventKind.allCases.count == 4)
        #expect(Set(EventKind.allCases.map(\.symbol)).count == 4)
        #expect(Set(EventKind.allCases.map(\.name)).count == 4)
    }

    @Test func aChangeWithNoPreviousOneSaysSoRatherThanShowingZero() {
        let event = change(date(1, 8), wearHours: 0)
        #expect(event.detail.contains("First recorded change"))
    }

    @Test func aChangeCarriesItsWearTimeInItsDetailLine() {
        let event = change(date(4, 8), reason: .leak, wearHours: 50)
        #expect(event.detail.contains("Leak"))
        #expect(event.detail.contains("2 days 2 hr"))
    }

    @Test func onlyABarrierChangeResetsWearTime() {
        #expect(change(date(1), scope: .barrierAndPouch).resetsWearTime)
        #expect(!change(date(1), scope: .pouchOnly).resetsWearTime)
        #expect(!emptying(date(1), 100).resetsWearTime)
    }

    @Test func aSkinCheckSaysWhenAPhotoIsAttached() {
        let check = skinCheck(date(1), .sore)
        #expect(!check.detail.contains("Photo"))
        check.photoData = Data([0x1])
        #expect(check.detail.contains("Photo attached"))
    }

    @Test func theSkinScaleIsOrdinalAndStaysInOrder() {
        let ranks = SkinCondition.allCases.map(\.rank)
        #expect(ranks == ranks.sorted())
        #expect(SkinCondition.intact.rank < SkinCondition.broken.rank)
    }
}
