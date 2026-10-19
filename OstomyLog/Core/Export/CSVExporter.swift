import Foundation

/// Every record, one row each, for the person who wants the numbers in a spreadsheet.
///
/// One flat table rather than four, because a day with an ostomy is one timeline and splitting it
/// into emptyings, changes, leaks and skin checks makes the reader join it back together.
enum CSVExporter {
    static let header = "date,kind,volume_ml,volume_floz,character,change_scope,change_reason,wear_hours,wear_days,leak_cause,skin,photo,notes"

    static func csv(for events: [OstomyEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [header]
        for event in events.sorted(by: { $0.date < $1.date }) {
            let isEmptying = event.kind == .emptying
            let isChange = event.kind == .applianceChange
            let fields = [
                formatter.string(from: event.date),
                event.kind.name,
                isEmptying ? formatted(event.volumeML) : "",
                isEmptying ? String(format: "%.1f", Volume.fluidOunces(fromMillilitres: event.volumeML)) : "",
                event.character?.name ?? "",
                isChange ? event.scope.name : "",
                isChange ? event.reason.name : "",
                isChange && event.wearHours > 0 ? String(format: "%.1f", event.wearHours) : "",
                isChange && event.wearHours > 0 ? String(format: "%.2f", event.wearHours / 24) : "",
                event.leakCause?.name ?? "",
                event.skin?.name ?? "",
                event.photoData == nil ? "" : "on file",
                event.notes.replacingOccurrences(of: "\n", with: " "),
            ]
            lines.append(fields.map(quote).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the CSV to a temporary file and returns its URL for the share sheet.
    static func export(_ events: [OstomyEvent]) throws -> URL {
        let url = ExportFile.temporaryURL(extension: "csv")
        try csv(for: events).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func quote(_ field: String) -> String {
        "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// A file URL wrapped so it can drive `.sheet(item:)`.
struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }

    static func temporaryURL(extension ext: String) -> URL {
        let stamp = DateFormatter.fileStamp.string(from: .now)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppConfig.exportFileStem)-\(stamp)")
            .appendingPathExtension(ext)
    }
}

extension DateFormatter {
    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()

    static let report: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static let reportDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    static let reportDayLong: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
