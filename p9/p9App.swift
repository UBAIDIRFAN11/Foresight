import SwiftUI
import SwiftData

@main
struct p9App: App {
    @UIApplicationDelegateAdaptor(ForesightAppDelegate.self) private var appDelegate
    @StateObject private var router = AppRouter()
    @StateObject private var reminderCoordinator = ReminderCoordinator(notificationClient: SystemNotificationClient())
    @State private var storeLoader = StoreLoader(factory: StoreLoader.launchFactory())
    @State private var dataController = AppDataController()

    var body: some Scene {
        WindowGroup {
            StoreRootView(loader: storeLoader, dataController: dataController)
                .environmentObject(router)
                .environmentObject(reminderCoordinator)
        }
    }
}
