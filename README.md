# Ostomy Log

A diary for someone with a colostomy, ileostomy or urostomy, built for the first months after surgery when a nurse asks how much output there was and how long a barrier lasted. It is for ostomy patients and their WOC nurses.

One of a set of niche iPhone apps built from a shared SwiftUI template. It was never released on the App Store; the code is here for anyone to use. The template is [somexai-ios-template](https://github.com/victorboba/somexai-ios-template) and the collection is [somexai-ios-apps](https://github.com/victorboba/somexai-ios-apps).

## What it does

- Two-tap emptying log: tap Log emptying, tap the closest volume, done. Press and hold to repeat the last volume.
- Wear time worked out from your own appliance changes, not typed in. It follows the barrier, so changing only the pouch on a two-piece system does not reset the clock (`WearClock` in `Models/LogSummary.swift`).
- Appliance changes (planned or forced by a leak), leaks and skin checks, with your own view of the cause and an optional photo that stays on the device.
- Supplies with a reorder countdown based on your observed usage rate. Product and size are free text, with no brand list.
- My setup: stoma type, one- or two-piece appliance and units, which decide what the app asks. An optional daily output figure from your clinician can be entered; the app shows your own days against it and passes no judgment.
- Appointment PDF with daily output, average wear time, planned changes versus leaks and skin notes, plus a CSV of every record.
- Widget (output today, wear time), a Siri App Shortcut and a How-to guide.

## The boundary

The app logs. It never advises, diagnoses, recommends a product or computes anything clinical.

## Privacy

Data stays on the device in SwiftData. There is no account, no analytics and no network access, and iCloud sync is off (`iCloudSyncEnabled = false`). Nothing leaves the phone unless you export a PDF or CSV and share it yourself.

## Model notes

- One `OstomyEvent` model with a `kind` (emptying, appliance change, leak, skin check) rather than four tables. `SupplyItem` holds supplies.
- Properties are defaulted so the schema is CloudKit-compatible.
- Unit tests cover wear time, usage rates, summaries and export; UI tests drive the emptying, change and summary flow.

## Build and run

- Requirements: Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), iOS 17 or later.
- Run `xcodegen generate`, open `OstomyLog.xcodeproj`, pick the `OstomyLog` scheme and an iPhone simulator, and Run.
- Tests: `xcodebuild -scheme OstomyLog -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' test`. `scripts/ci.sh OstomyLog` is an alternative that keeps build output under `build/` and gives each run its own simulator.
- Paywall: the app has a hard paywall (annual subscription or lifetime purchase). Running from Xcode uses the bundled `Products.storekit` file, so purchases are simulated and free. Debug builds can also skip it with the `-unlock` launch argument or the Debug switch in Settings.
- To run on your own device or ship it: set your team in `project.yml` (`DEVELOPMENT_TEAM`), change the `com.example` bundle ID prefix in `project.yml`, both `.entitlements` files and `Products.storekit`, and update `supportEmail`, `privacyPolicyURL` and `appStoreID` in `Shared/AppConfig.swift`.

## Project layout

- `OstomyLog/App/`, `OstomyLog/Core/`: app entry and root gate, StoreKit entitlement, export, review prompt, App Shortcut, widget sync.
- `OstomyLog/Features/`: the screens.
- `OstomyLog/Models/`: SwiftData models.
- `Shared/StomaProfile.swift`: the stoma and appliance setup shared with the widget.
- `OstomyLogWidget/`: the Home Screen widget, fed from a snapshot in the App Group.
- `Shared/AppConfig.swift`: everything that changes per app (name, copy, product IDs, links, How-to guide, disclaimer).
- `OstomyLogTests/`, `OstomyLogUITests/`: unit and UI tests.
- `scripts/`, `docs/`: icon and screenshot helpers, capability notes.

## License

MIT. See [LICENSE](LICENSE).
