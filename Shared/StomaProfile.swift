import Foundation

/// What the user wears, and the one number their own clinician gave them.
///
/// This is deliberately not a SwiftData model: it is a handful of settings the widget also needs
/// to read, so it lives in the App Group defaults that `WidgetSnapshot` already uses. Foundation
/// only, because `Shared/` is compiled into the widget as well.
///
/// **The stoma type and the appliance system are not decoration.** They decide which questions the
/// app asks: a urostomy is never asked about stool consistency, and a one-piece appliance has no
/// such thing as changing only the pouch. Asking anyway is how a logging app gets deleted on day two.
enum StomaType: String, CaseIterable, Identifiable, Sendable {
    case colostomy, ileostomy, urostomy

    var id: String { rawValue }

    var name: String {
        switch self {
        case .colostomy: return "Colostomy"
        case .ileostomy: return "Ileostomy"
        case .urostomy: return "Urostomy"
        }
    }

    /// What comes out, in the words the user would use.
    var outputNoun: String {
        self == .urostomy ? "Urine" : "Output"
    }

    /// The heading over the ordinal scale on the emptying screen.
    var characterLabel: String {
        self == .urostomy ? "Appearance" : "Consistency"
    }
}

enum ApplianceSystem: String, CaseIterable, Identifiable, Sendable {
    case onePiece, twoPiece

    var id: String { rawValue }

    var name: String {
        switch self {
        case .onePiece: return "One-piece"
        case .twoPiece: return "Two-piece"
        }
    }

    var detail: String {
        switch self {
        case .onePiece: return "The pouch and the barrier are one unit, so every change is a whole change."
        case .twoPiece: return "The pouch clips onto the barrier, so the pouch can be changed on its own."
        }
    }

    /// On a one-piece there is only one kind of change, so the app does not ask.
    var changeScopes: [ChangeScope] {
        switch self {
        case .onePiece: return [.whole]
        case .twoPiece: return [.barrierAndPouch, .pouchOnly, .barrierOnly]
        }
    }
}

/// Which parts came off. Only a change that includes the barrier restarts wear time.
enum ChangeScope: String, CaseIterable, Identifiable, Sendable {
    case whole, barrierAndPouch, pouchOnly, barrierOnly

    var id: String { rawValue }

    var name: String {
        switch self {
        case .whole: return "Whole appliance"
        case .barrierAndPouch: return "Barrier and pouch"
        case .pouchOnly: return "Pouch only"
        case .barrierOnly: return "Barrier only"
        }
    }

    /// **The rule the whole app turns on.** Wear time is the barrier's, not the pouch's. Swapping
    /// a pouch on a two-piece leaves the barrier on the skin, so the clock keeps running.
    var includesBarrier: Bool { self != .pouchOnly }
}

enum VolumeUnit: String, CaseIterable, Identifiable, Sendable {
    case millilitres, fluidOunces

    var id: String { rawValue }

    var name: String {
        switch self {
        case .millilitres: return "Millilitres (ml)"
        case .fluidOunces: return "Fluid ounces (fl oz)"
        }
    }

    var short: String {
        switch self {
        case .millilitres: return "ml"
        case .fluidOunces: return "fl oz"
        }
    }
}

/// Millilitres are what is stored; fluid ounces are a display choice. One place for the
/// conversion so the dashboard, the PDF, the CSV and the widget can never disagree.
enum Volume {
    static let millilitresPerFluidOunce = 29.5735295625

    static func fluidOunces(fromMillilitres ml: Double) -> Double {
        ml / millilitresPerFluidOunce
    }

    static func millilitres(fromFluidOunces oz: Double) -> Double {
        oz * millilitresPerFluidOunce
    }

    /// "250 ml" or "8.5 fl oz". Millilitres are whole numbers; ounces keep one decimal, because
    /// rounding 8.5 fl oz to 9 loses more than it saves at these volumes.
    static func format(millilitres ml: Double, in unit: VolumeUnit) -> String {
        switch unit {
        case .millilitres:
            return "\(Int(ml.rounded())) ml"
        case .fluidOunces:
            let oz = fluidOunces(fromMillilitres: ml)
            return String(format: "%.1f fl oz", oz)
        }
    }

    /// Both units, for the report a nurse reads: "1,450 ml (49.0 fl oz)".
    static func formatBoth(millilitres ml: Double) -> String {
        let whole = Int(ml.rounded())
        let grouped = NumberFormatter.grouped.string(from: NSNumber(value: whole)) ?? "\(whole)"
        return "\(grouped) ml (\(String(format: "%.1f", fluidOunces(fromMillilitres: ml))) fl oz)"
    }
}

extension NumberFormatter {
    static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()
}

/// The user's own setup, stored in the App Group so the widget sees the same thing.
enum StomaProfile {
    private static var defaults: UserDefaults { WidgetSnapshot.defaults }

    enum Key {
        static let stomaType = "profile.stomaType"
        static let applianceSystem = "profile.applianceSystem"
        static let volumeUnit = "profile.volumeUnit"
        /// The daily output figure the user's own clinician gave them, in ml. Zero means none set.
        /// The app never invents this number and never says a figure is too high or too low.
        static let dailyOutputTargetML = "profile.dailyOutputTargetML"
        static let quickVolumes = "profile.quickVolumes"
    }

    static var stomaType: StomaType {
        get { StomaType(rawValue: defaults.string(forKey: Key.stomaType) ?? "") ?? .ileostomy }
        set { defaults.set(newValue.rawValue, forKey: Key.stomaType) }
    }

    static var applianceSystem: ApplianceSystem {
        get { ApplianceSystem(rawValue: defaults.string(forKey: Key.applianceSystem) ?? "") ?? .onePiece }
        set { defaults.set(newValue.rawValue, forKey: Key.applianceSystem) }
    }

    static var volumeUnit: VolumeUnit {
        get { VolumeUnit(rawValue: defaults.string(forKey: Key.volumeUnit) ?? "") ?? .millilitres }
        set { defaults.set(newValue.rawValue, forKey: Key.volumeUnit) }
    }

    /// The user's own clinician-given daily figure, or nil if they never entered one.
    static var dailyOutputTargetML: Double? {
        get {
            let value = defaults.double(forKey: Key.dailyOutputTargetML)
            return value > 0 ? value : nil
        }
        set { defaults.set(newValue ?? 0, forKey: Key.dailyOutputTargetML) }
    }

    /// The volume buttons on the emptying screen, in ml.
    static let defaultQuickVolumes: [Double] = [50, 100, 150, 200, 250, 300, 400]
}
