import Foundation
import UIKit

/// The appointment document.
///
/// This is what the user is actually buying. A WOC nurse has fifteen minutes and asks three
/// questions: how much is it putting out, how long is a barrier lasting, and how often is a leak
/// forcing the change. So those three are the top of page one, in that order, in a block that can
/// be read in half a minute — and the day-by-day table underneath is there for the nurse who
/// wants to see the spread rather than the average.
///
/// Every line is arithmetic on what the user entered. The report makes no clinical statement,
/// carries no threshold and no advice, and says so at the bottom. Where the user has entered a
/// daily figure their own clinician gave them, it appears as theirs and the days are counted
/// against it, nothing more.
///
/// Photos are deliberately left out. They are on the phone for the user to show or send
/// themselves; a stoma photo does not belong in a document that gets mailed around.
enum PDFExporter {
    static func export(summary: LogSummary, supplies: [SupplyItem] = [],
                       rates: UsageRates = UsageRates(), asOf today: Date = .now) throws -> URL {
        let stamp = ISO8601DateFormatter.day.string(from: today)
        return try render(named: "\(AppConfig.exportFileStem)-\(stamp)") { draw in
            header(draw, summary: summary)
            atAGlance(draw, summary: summary)
            dailyTable(draw, summary: summary)
            changesTable(draw, summary: summary)
            leaksAndSkin(draw, summary: summary)
            suppliesTable(draw, supplies: supplies, rates: rates)
            footer(draw)
        }
    }

    // MARK: Sections

    private static func header(_ draw: Draw, summary: LogSummary) {
        draw.title("Ostomy diary")
        let type = StomaProfile.stomaType.name
        let system = StomaProfile.applianceSystem.name.lowercased()
        draw.line("\(type), \(system) appliance", size: 11, colour: .secondaryLabel)
        let from = DateFormatter.reportDayLong.string(from: summary.range.lowerBound)
        let to = DateFormatter.reportDayLong.string(from: summary.range.upperBound.addingTimeInterval(-1))
        draw.line("Period \(from) to \(to)", size: 11, colour: .secondaryLabel)
        draw.rule()
    }

    private static func atAGlance(_ draw: Draw, summary: LogSummary) {
        draw.line("At a glance", size: 13, weight: .semibold, gapAfter: 6)

        draw.pair("Average daily output",
                  summary.averageDailyOutputML.map { Volume.formatBoth(millilitres: $0) } ?? "No emptyings recorded")
        draw.pair("Emptyings a day",
                  summary.averageEmptyingsPerDay.map { String(format: "%.1f", $0) } ?? "None recorded")
        draw.pair("Average an emptying",
                  summary.averageVolumePerEmptyingML.map { Volume.formatBoth(millilitres: $0) } ?? "None recorded")
        draw.pair("Average wear time",
                  summary.averageWearHours.map { WearTimeFormat.days(hours: $0) } ?? "Not enough changes to measure")
        if let shortest = summary.shortestWearHours, let longest = summary.longestWearHours {
            draw.pair("Wear time range",
                      "\(WearTimeFormat.short(hours: shortest)) to \(WearTimeFormat.short(hours: longest))")
        }
        draw.pair("Appliance changes",
                  "\(summary.changes.count) in total, \(summary.plannedChanges) planned, \(summary.leakForcedChanges) after a leak")
        draw.pair("Leaks logged", "\(summary.leaks.count)")
        draw.pair("Days with a record", "\(summary.daysWithOutput)")

        if let target = summary.daysOverTarget(StomaProfile.dailyOutputTargetML),
           let figure = StomaProfile.dailyOutputTargetML {
            draw.gap(4)
            draw.line("Your own daily target of \(Volume.formatBoth(millilitres: figure)), as given to you by your clinician and entered by you:",
                      size: 9, colour: .secondaryLabel)
            draw.pair("Days above that figure", "\(target.over) of \(target.counted) days with a record")
        }
        draw.rule()
    }

    private static func dailyTable(_ draw: Draw, summary: LogSummary) {
        draw.line("Day by day", size: 13, weight: .semibold, gapAfter: 6)
        let columns: [Draw.Column] = [
            .init(title: "Date", x: 0, width: 96),
            .init(title: "Output", x: 100, width: 92),
            .init(title: "Emptyings", x: 196, width: 66, alignRight: true),
            .init(title: "Changes", x: 266, width: 60, alignRight: true),
            .init(title: "Leaks", x: 330, width: 44, alignRight: true),
            .init(title: "Skin", x: 380, width: 136),
        ]
        draw.columnHeader(columns)
        let days = summary.dailyTotals
        if days.isEmpty {
            draw.line("No emptyings were recorded in this period.", size: 10, colour: .secondaryLabel)
        }
        for day in days.reversed() {
            draw.row(columns, values: [
                DateFormatter.reportDayLong.string(from: day.date),
                Volume.format(millilitres: day.outputML, in: .millilitres),
                "\(day.emptyings)",
                day.changes == 0 ? "—" : "\(day.changes)",
                day.leaks == 0 ? "—" : "\(day.leaks)",
                day.skinNote,
            ])
        }
        draw.rule()
    }

    private static func changesTable(_ draw: Draw, summary: LogSummary) {
        draw.line("Appliance changes and wear time", size: 13, weight: .semibold, gapAfter: 6)
        let columns: [Draw.Column] = [
            .init(title: "Date", x: 0, width: 96),
            .init(title: "What came off", x: 100, width: 120),
            .init(title: "Worn for", x: 224, width: 100),
            .init(title: "Why", x: 328, width: 188),
        ]
        draw.columnHeader(columns)
        let changes = summary.changes.sorted { $0.date > $1.date }
        if changes.isEmpty {
            draw.line("No appliance changes were recorded in this period.", size: 10, colour: .secondaryLabel)
        }
        for change in changes {
            draw.row(columns, values: [
                DateFormatter.reportDayLong.string(from: change.date),
                change.scope.name,
                change.resetsWearTime
                    ? (change.wearHours > 0 ? WearTimeFormat.short(hours: change.wearHours) : "First recorded")
                    : "Barrier stayed on",
                change.reason.name,
            ], emphasised: change.reason.wasForced)
        }
        draw.rule()
    }

    private static func leaksAndSkin(_ draw: Draw, summary: LogSummary) {
        draw.line("Leaks", size: 13, weight: .semibold, gapAfter: 6)
        if summary.leaks.isEmpty {
            draw.line("No leaks were recorded in this period.", size: 10, colour: .secondaryLabel)
        }
        for leak in summary.leaks.sorted(by: { $0.date > $1.date }) {
            let cause = leak.leakCause?.name ?? "Cause not recorded"
            let note = leak.notes.isEmpty ? "" : " — \(leak.notes)"
            draw.line("\(DateFormatter.report.string(from: leak.date))   \(cause)\(note)", size: 10, gapAfter: 2)
        }

        draw.gap(8)
        draw.line("Skin around the stoma", size: 13, weight: .semibold, gapAfter: 6)
        if summary.skinChecks.isEmpty {
            draw.line("No skin checks were recorded in this period.", size: 10, colour: .secondaryLabel)
        }
        for check in summary.skinChecks.sorted(by: { $0.date > $1.date }) {
            let described = check.skin?.name ?? "Not described"
            let note = check.notes.isEmpty ? "" : " — \(check.notes)"
            let photo = check.photoData == nil ? "" : "  [photo kept on the phone]"
            draw.line("\(DateFormatter.reportDayLong.string(from: check.date))   \(described)\(note)\(photo)",
                      size: 10, gapAfter: 2)
        }
        draw.rule()
    }

    private static func suppliesTable(_ draw: Draw, supplies: [SupplyItem], rates: UsageRates) {
        guard !supplies.isEmpty else { return }
        draw.line("Supplies on hand", size: 13, weight: .semibold, gapAfter: 6)
        let columns: [Draw.Column] = [
            .init(title: "Item", x: 0, width: 250),
            .init(title: "On hand", x: 254, width: 70, alignRight: true),
            .init(title: "Days left at your own rate", x: 330, width: 186, alignRight: true),
        ]
        draw.columnHeader(columns)
        for item in supplies {
            let days = item.daysRemaining(rates: rates)
            draw.row(columns, values: [
                item.title,
                "\(item.quantityOnHand)",
                days.map { "\($0)" } ?? "Not enough history",
            ])
        }
        draw.rule()
    }

    private static func footer(_ draw: Draw) {
        draw.line("\(AppConfig.appName) is a diary. Every figure above is a total, an average or a count of what the person keeping it typed in. It contains no clinical assessment, no threshold and no advice, and the app does not monitor anything or make any judgement about these numbers. Photographs, where any were taken, stay on the phone and are not part of this document.",
                  size: 9, colour: .secondaryLabel)
    }

    // MARK: - Page plumbing

    final class Draw {
        struct Column {
            let title: String
            /// Offset from the left margin.
            let x: CGFloat
            let width: CGFloat
            var alignRight: Bool = false
        }

        let ctx: UIGraphicsPDFRendererContext
        let pageWidth: CGFloat = 612, pageHeight: CGFloat = 792, margin: CGFloat = 48
        var y: CGFloat = 48

        init(_ ctx: UIGraphicsPDFRendererContext) { self.ctx = ctx }

        func title(_ text: String) { line(text, size: 22, weight: .semibold) }

        func gap(_ amount: CGFloat) { y += amount }

        func line(_ text: String, size: CGFloat = 11, weight: UIFont.Weight = .regular,
                  colour: UIColor = .label, indent: CGFloat = 0, gapAfter: CGFloat = 4) {
            let font = UIFont.systemFont(ofSize: size, weight: weight)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
            let width = pageWidth - margin * 2 - indent
            let bounding = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
            if y + bounding.height > pageHeight - margin { newPage() }
            (text as NSString).draw(
                with: CGRect(x: margin + indent, y: y, width: width, height: bounding.height),
                options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
            y += bounding.height + gapAfter
        }

        /// A label on the left and its value on the right of the same line. Drawn as two separate
        /// pieces at fixed positions, never as one padded string.
        func pair(_ label: String, _ value: String, size: CGFloat = 10) {
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.secondaryLabel]
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: UIColor.label]
            let labelWidth: CGFloat = 200
            let valueWidth: CGFloat = pageWidth - margin * 2 - 210
            let unbounded: CGFloat = .greatestFiniteMagnitude
            let labelHeight = (label as NSString).boundingRect(
                with: CGSize(width: labelWidth, height: unbounded),
                options: [.usesLineFragmentOrigin], attributes: labelAttrs, context: nil).height
            let valueHeight = (value as NSString).boundingRect(
                with: CGSize(width: valueWidth, height: unbounded),
                options: [.usesLineFragmentOrigin], attributes: valueAttrs, context: nil).height
            let height = max(labelHeight, valueHeight)
            if y + height > pageHeight - margin { newPage() }
            (label as NSString).draw(with: CGRect(x: margin, y: y, width: labelWidth, height: height),
                                     options: [.usesLineFragmentOrigin], attributes: labelAttrs, context: nil)
            (value as NSString).draw(with: CGRect(x: margin + 210, y: y, width: valueWidth, height: height),
                                     options: [.usesLineFragmentOrigin], attributes: valueAttrs, context: nil)
            y += height + 3
        }

        func columnHeader(_ columns: [Column]) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel]
            if y + 14 > pageHeight - margin { newPage() }
            for column in columns {
                (column.title as NSString).draw(
                    in: CGRect(x: margin + column.x, y: y, width: column.width, height: 12),
                    withAttributes: attrs.merging(alignment(column)) { $1 })
            }
            y += 13
            hairline()
        }

        func row(_ columns: [Column], values: [String], emphasised: Bool = false) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: emphasised ? .semibold : .regular),
                .foregroundColor: emphasised ? UIColor.label : UIColor.label]
            var height: CGFloat = 12
            for (column, value) in zip(columns, values) {
                let bounding = (value as NSString).boundingRect(
                    with: CGSize(width: column.width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
                height = max(height, bounding.height)
            }
            if y + height > pageHeight - margin { newPage(); columnHeader(columns) }
            for (column, value) in zip(columns, values) {
                (value as NSString).draw(
                    with: CGRect(x: margin + column.x, y: y, width: column.width, height: height),
                    options: [.usesLineFragmentOrigin],
                    attributes: attrs.merging(alignment(column)) { $1 }, context: nil)
            }
            y += height + 3
        }

        private func alignment(_ column: Column) -> [NSAttributedString.Key: Any] {
            guard column.alignRight else { return [:] }
            let style = NSMutableParagraphStyle()
            style.alignment = .right
            return [.paragraphStyle: style]
        }

        func hairline() {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y - 3))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: y - 3))
            UIColor.separator.setStroke(); path.lineWidth = 0.4; path.stroke()
        }

        func rule(gap: CGFloat = 12) {
            y += gap / 2
            if y > pageHeight - margin { newPage(); return }
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            UIColor.separator.setStroke(); path.lineWidth = 0.5; path.stroke()
            y += gap / 2
        }

        private func newPage() {
            ctx.beginPage()
            y = margin
        }
    }

    private static func render(named name: String, _ body: (Draw) -> Void) throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            body(Draw(ctx))
        }
        return url
    }
}

extension ISO8601DateFormatter {
    static let day: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
