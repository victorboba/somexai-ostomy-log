import Foundation
import SwiftData

/// One thing that happened, on one timeline.
///
/// A day with an ostomy is a single stream of small events — emptied the pouch, changed the
/// appliance, had a leak, looked at the skin — and the questions a WOC nurse asks at the
/// follow-up appointment cut across all four at once: how much is it putting out, how long is a
/// barrier lasting, how often is a leak forcing the change, how is the skin. So they are one
/// record type with a kind, not four tables that have to be joined back together at export time.
///
/// Every property has a default and nothing is unique, which keeps the model CloudKit-compatible
/// if `AppConfig.iCloudSyncEnabled` is ever turned on.
///
/// **What this app does not do.** It records what the user entered and states arithmetic about
/// it. It does not judge a volume, recommend a wear time, suggest a product, or interpret a skin
/// note. Where the user has been given a figure by their own clinician, the app stores that
/// figure as theirs and shows their numbers beside it.
@Model
final class OstomyEvent {
    var id: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = EventKind.emptying.rawValue

    // Emptying
    var volumeML: Double = 0
    var characterRaw: String = ""

    // Appliance change
    var scopeRaw: String = ChangeScope.whole.rawValue
    var reasonRaw: String = ChangeReason.planned.rawValue
    /// Filled in when the change is saved: hours the barrier that just came off had been on.
    /// Stored rather than recomputed so an edited history cannot quietly rewrite an old record.
    var wearHours: Double = 0

    // Leak
    var leakCauseRaw: String = ""

    // Skin check
    var skinRaw: String = ""

    @Attribute(.externalStorage) var photoData: Data? = nil
    var notes: String = ""
    var createdAt: Date = Date()

    init(kind: EventKind = .emptying, date: Date = .now) {
        self.id = UUID()
        self.date = date
        self.kindRaw = kind.rawValue
        self.createdAt = .now
    }

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .emptying }
        set { kindRaw = newValue.rawValue }
    }

    var character: OutputCharacter? {
        get { OutputCharacter(rawValue: characterRaw) }
        set { characterRaw = newValue?.rawValue ?? "" }
    }

    var scope: ChangeScope {
        get { ChangeScope(rawValue: scopeRaw) ?? .whole }
        set { scopeRaw = newValue.rawValue }
    }

    var reason: ChangeReason {
        get { ChangeReason(rawValue: reasonRaw) ?? .planned }
        set { reasonRaw = newValue.rawValue }
    }

    var leakCause: LeakCause? {
        get { LeakCause(rawValue: leakCauseRaw) }
        set { leakCauseRaw = newValue?.rawValue ?? "" }
    }

    var skin: SkinCondition? {
        get { SkinCondition(rawValue: skinRaw) }
        set { skinRaw = newValue?.rawValue ?? "" }
    }

    var day: Date { Calendar.current.startOfDay(for: date) }

    /// A change that took the barrier off the skin, which is the only kind that restarts wear time.
    var resetsWearTime: Bool { kind == .applianceChange && scope.includesBarrier }

    /// One line for the history list and the CSV notes column.
    var headline: String {
        switch kind {
        case .emptying:
            return Volume.format(millilitres: volumeML, in: StomaProfile.volumeUnit)
        case .applianceChange:
            return scope.name
        case .leak:
            return leakCause?.name ?? "Leak"
        case .skinCheck:
            return skin?.name ?? "Skin check"
        }
    }

    var detail: String {
        switch kind {
        case .emptying:
            return character?.name ?? ""
        case .applianceChange:
            let worn = wearHours > 0 ? "Worn \(WearTimeFormat.short(hours: wearHours))" : "First recorded change"
            return "\(reason.name) · \(worn)"
        case .leak:
            return notes.isEmpty ? "" : notes
        case .skinCheck:
            return photoData == nil ? notes : (notes.isEmpty ? "Photo attached" : "\(notes) · Photo attached")
        }
    }
}

// MARK: - The vocabulary of the log

enum EventKind: String, CaseIterable, Identifiable, Sendable {
    case emptying, applianceChange, leak, skinCheck

    var id: String { rawValue }

    var name: String {
        switch self {
        case .emptying: return "Emptying"
        case .applianceChange: return "Appliance change"
        case .leak: return "Leak"
        case .skinCheck: return "Skin check"
        }
    }

    var plural: String {
        switch self {
        case .emptying: return "Emptyings"
        case .applianceChange: return "Appliance changes"
        case .leak: return "Leaks"
        case .skinCheck: return "Skin checks"
        }
    }

    var symbol: String {
        switch self {
        case .emptying: return "drop.fill"
        case .applianceChange: return "arrow.triangle.2.circlepath"
        case .leak: return "exclamationmark.triangle.fill"
        case .skinCheck: return "bandage.fill"
        }
    }
}

/// An ordinal scale, in plain words the user would say out loud. It is a description of what they
/// saw, never a classification of anything.
///
/// The stool scale and the urine scale are one enum with two option lists, because the stoma type
/// decides which of them the user is ever shown.
enum OutputCharacter: String, CaseIterable, Identifiable, Sendable {
    // Stool (colostomy and ileostomy)
    case watery, thin, porridge, thick, formed
    // Urine (urostomy)
    case clear, pale, dark, cloudy, bloodTinged

    var id: String { rawValue }

    var name: String {
        switch self {
        case .watery: return "Watery"
        case .thin: return "Thin"
        case .porridge: return "Porridge"
        case .thick: return "Thick"
        case .formed: return "Formed"
        case .clear: return "Clear"
        case .pale: return "Pale"
        case .dark: return "Dark"
        case .cloudy: return "Cloudy"
        case .bloodTinged: return "Blood-tinged"
        }
    }

    static let stoolScale: [OutputCharacter] = [.watery, .thin, .porridge, .thick, .formed]
    static let urineScale: [OutputCharacter] = [.clear, .pale, .dark, .cloudy, .bloodTinged]

    /// A urostomy is never asked about porridge, and an ileostomy is never asked whether the
    /// output was cloudy.
    static func options(for type: StomaType) -> [OutputCharacter] {
        type == .urostomy ? urineScale : stoolScale
    }
}

/// Why the appliance came off. The split that matters is planned against forced, and it is the
/// single most informative ratio in the whole log.
enum ChangeReason: String, CaseIterable, Identifiable, Sendable {
    case planned, leak, skinDiscomfort, poorSeal, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .planned: return "Planned"
        case .leak: return "Leak"
        case .skinDiscomfort: return "Skin discomfort"
        case .poorSeal: return "Poor seal"
        case .other: return "Something else"
        }
    }

    var wasForced: Bool { self != .planned }
}

/// What the user thought caused the leak. Their words about their own body, not a finding.
enum LeakCause: String, CaseIterable, Identifiable, Sendable {
    case notSure, seal, output, pouchFull, sweat, activity, overnight

    var id: String { rawValue }

    var name: String {
        switch self {
        case .notSure: return "Not sure"
        case .seal: return "Seal lifted"
        case .output: return "Output too liquid"
        case .pouchFull: return "Pouch too full"
        case .sweat: return "Sweat or heat"
        case .activity: return "Bending or activity"
        case .overnight: return "Overnight"
        }
    }
}

/// How the skin around the stoma looked, in ordinary words. An ordinal scale so the history can
/// be read down a page; nothing here is a grade, a score or a diagnosis.
enum SkinCondition: String, CaseIterable, Identifiable, Sendable {
    case intact, pink, red, sore, broken

    var id: String { rawValue }

    var name: String {
        switch self {
        case .intact: return "Intact"
        case .pink: return "Slightly pink"
        case .red: return "Red"
        case .sore: return "Sore or weeping"
        case .broken: return "Open or bleeding"
        }
    }

    /// Higher is worse, for sorting a history — not a severity score and never shown as a number.
    var rank: Int {
        switch self {
        case .intact: return 0
        case .pink: return 1
        case .red: return 2
        case .sore: return 3
        case .broken: return 4
        }
    }
}
