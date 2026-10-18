import SwiftUI
import SwiftData
import UIKit

@main
struct ScheduleReminderApp: App {
    let container: ModelContainer

    init() {
        UserDefaults.standard.register(defaults: [
            "firstClassAlertEnabled": true,
            "firstClassAlertMinutes": 30,
            "defaultAlertMinutes": 20,
            "autoLiveActivity": true
        ])
        let schema = Schema([Schedule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("无法创建 ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ScheduleListView()
                .modelContainer(container)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    LiveActivityManager.shared.refreshAll()
                }
        }
    }
}
