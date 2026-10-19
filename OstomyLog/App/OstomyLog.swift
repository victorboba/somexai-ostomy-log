import SwiftUI
import SwiftData

@main
struct OstomyLog: App {
    @State private var entitlements = EntitlementStore()
    private let container: ModelContainer

    init() {
        let schema = Schema([OstomyEvent.self, SupplyItem.self])
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: AppConfig.iCloudSyncEnabled ? .automatic : .none
        )
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetData") {
            try? container.mainContext.delete(model: OstomyEvent.self)
            try? container.mainContext.delete(model: SupplyItem.self)
            try? container.mainContext.save()
            StomaProfile.dailyOutputTargetML = nil
            StomaProfile.stomaType = .ileostomy
            StomaProfile.applianceSystem = .onePiece
            StomaProfile.volumeUnit = .millilitres
        }
        if ProcessInfo.processInfo.arguments.contains("-sampleData"),
           (try? container.mainContext.fetchCount(FetchDescriptor<OstomyEvent>())) == 0 {
            SampleData.insert(into: container.mainContext)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(entitlements)
                .tint(.appAccent)
        }
        .modelContainer(container)
    }
}
