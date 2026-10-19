import AppIntents
import Foundation

/// "Log an emptying in Ostomy Log" from Siri, Spotlight or the Shortcuts app. Opens the app with
/// the emptying sheet already up, which is the whole point: it happens six times a day and the
/// fewer taps between the thought and the record, the more of them actually get recorded.
struct LogEmptyingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log an Emptying"
    static var description = IntentDescription("Opens the app ready to record an emptying.")
    static var openAppWhenRun = true

    static let pendingKey = "intent.openNewEmptying"

    func perform() async throws -> some IntentResult {
        WidgetSnapshot.defaults.set(true, forKey: Self.pendingKey)
        return .result()
    }
}

struct OstomyLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogEmptyingIntent(),
            phrases: ["Log an emptying in \(.applicationName)", "New emptying in \(.applicationName)"],
            shortTitle: "Log Emptying",
            systemImageName: "drop.fill"
        )
    }
}
