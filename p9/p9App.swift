import SwiftUI
import SwiftData

//starting point of the app

@main
struct p9App: App {
    
    //connect app to ForesightAppDelegate
    @UIApplicationDelegateAdaptor(ForesightAppDelegate.self) private var appDelegate
    
    //initialise shared services
    @StateObject private var router = AppRouter()
    @StateObject private var reminderCoordinator = ReminderCoordinator(notificationClient: SystemNotificationClient())
    
    //set up data management
    @State private var storeLoader = StoreLoader(factory: StoreLoader.launchFactory())
    @State private var dataController = AppDataController()

    //disp main interface, make app router and notification coordinator visible to child views
    var body: some Scene {
        WindowGroup {
            StoreRootView(loader: storeLoader, dataController: dataController)
            
                .environmentObject(router)
                .environmentObject(reminderCoordinator)
        }
    }
}
