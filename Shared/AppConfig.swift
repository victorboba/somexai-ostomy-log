import Foundation

/// The one file to edit when starting a new app from this template.
/// Everything user-facing that changes per app (name, copy, product IDs, links) lives here.
/// Compiled into both the app and the widget, so keep it free of UIKit/SwiftUI imports.
enum AppConfig {
    // MARK: Identity
    static let appName = "Ostomy Log"
    static let bundleID = "com.example.ostomy-log"
    static let appGroupID = "group.com.example.ostomy-log"
    /// Your App Store ID once the app is live. The Rate button stays hidden while it is empty.(the number in the App Store URL).
    static let appStoreID = ""

    // MARK: Sync
    /// Set to true only after enabling iCloud + CloudKit on the App ID (see docs/capabilities.md).
    /// With false, SwiftData stores locally and the app works with no Apple capabilities at all.
    static let iCloudSyncEnabled = false

    // MARK: StoreKit (must match App Store Connect and StoreKit/Products.storekit)
    /// Apple allows only letters, digits, underscores and periods in product IDs, so hyphens in the bundle ID are dropped.
    static let productPrefix = bundleID.replacingOccurrences(of: "-", with: "")
    static let annualProductID = "\(productPrefix).pro.annual"
    static let lifetimeProductID = "\(productPrefix).pro.lifetime"

    // MARK: Links
    static let supportEmail = "support@somexai.com"
    /// Hosted copy of PrivacyPolicyView, one page per app under somexai.com/privacy (somexai_corp repo, scripts/privacy.py).
    static let privacyPolicyURL = URL(string: "https://somexai.com/privacy/ostomy-log/")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    // MARK: Copy
    /// What the app calls one record. "Entry" for a generic log; "Dose", "Visit", "Inspection" in real apps.
    static let entryNoun = "Record"
    static let entryNounPlural = "Records"
    /// File name stem for exports: "ostomy-log-2026-09-11.csv".
    static let exportFileStem = "ostomy-log"

    static let onboarding: [OnboardingPage] = [
        OnboardingPage(symbol: "drop.fill", title: "Emptying takes two taps",
                       body: "Tap the big button, tap a volume, done. It happens six times a day, so it was built to take seconds and nothing more."),
        OnboardingPage(symbol: "timer", title: "Wear time counts itself",
                       body: "The ring on the home screen is the time since your last barrier change. When you change, the app works out how long that one lasted — the number your nurse asks for."),
        OnboardingPage(symbol: "lock.fill", title: "It never leaves your phone",
                       body: "No account, no server, no sign-in. Your output, your leaks and your skin photos stay on this device until you export a PDF and choose where to send it."),
    ]

    static let paywallSymbol = "checkmark.seal.fill"
    static let paywallHeadline = "Unlock \(appName)"
    static let paywallBenefits = [
        "Two-tap emptying log, widget and Siri Shortcut",
        "Wear time worked out from your own changes",
        "An appointment PDF your nurse can read in a minute",
        "No account, no server, nothing uploaded",
    ]

    // MARK: How-to guide (Settings → How do I use this app; also the ? button on the home screen)
    static let howToIntro = "Five minutes to set up, then a few seconds a day. The first two steps are the whole app."
    static let howTo: [HowToStep] = [
        HowToStep(symbol: "person.crop.circle", title: "Tell the app what you wear",
                  body: "Open Settings and tap My setup. Choose colostomy, ileostomy or urostomy, and whether your appliance is one-piece or two-piece. That decides what the app asks you — a urostomy is never asked about stool consistency, and a one-piece is never asked whether you changed only the pouch.",
                  tip: "If your nurse gave you a daily output figure to watch, type it into Daily output target on that same screen. The app shows your own numbers against it and never judges them."),
        HowToStep(symbol: "drop.fill", title: "Log an emptying",
                  body: "Tap the big Log emptying button on the home screen, tap the closest volume, and tap Save. Today's total and the number of emptyings update straight away. Hold the button down instead and choose Repeat last volume to log it in one tap."),
        HowToStep(symbol: "timer", title: "Log an appliance change",
                  body: "Tap Appliance change. Say whether it was planned or a leak forced it. The moment you save, the ring resets and the app records how long the barrier you just took off actually lasted.",
                  tip: "On a two-piece, changing only the pouch does not reset the ring. Wear time belongs to the barrier, which is what your nurse is asking about."),
        HowToStep(symbol: "exclamationmark.triangle", title: "Log a leak or a skin check",
                  body: "Leak and Skin check are the two smaller buttons under the ring. A skin check takes an optional photo with Add Photo, and the photo stays on this phone."),
        HowToStep(symbol: "shippingbox", title: "Keep an eye on supplies",
                  body: "Tap the Supplies card, add what you use by name and size, and enter how many you have left. The app counts down from how often you actually change, so you can reorder before you run out."),
        HowToStep(symbol: "doc.richtext", title: "Take the PDF to your appointment",
                  body: "Tap the share icon at the top of the home screen and choose Appointment PDF. It puts daily output, average wear time, planned changes against leaks, and your skin notes on one page. CSV is there too if you want the raw numbers in a spreadsheet."),
    ]

    /// Display prices used only by DEBUG screenshot runs (`-mockPrices`). Keep in sync with StoreKit/Products.storekit.
    static let mockPrices = (annual: "$3.99", lifetime: "$8.99")

    // MARK: Behaviour
    /// Ask for an App Store review after this many successful saves (once per app version).
    static let reviewAfterSuccesses = 8
}

struct HowToStep: Identifiable, Hashable {
    var id: String { title }
    let symbol: String
    let title: String
    let body: String
    var tip: String? = nil
}

struct OnboardingPage: Identifiable, Hashable {
    var id: String { title }
    let symbol: String
    let title: String
    let body: String
}
