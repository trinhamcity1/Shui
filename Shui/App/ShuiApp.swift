import SwiftData
import SwiftUI
import UIKit

/// Firebase is configured from the UIKit launch callback rather than from
/// `ShuiApp.init()`, so configuration is guaranteed to happen before anything
/// in the view tree can reach for Firestore or Auth.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configure()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-useFirebaseEmulator") {
            FirebaseBootstrap.useEmulators()
        }
        #endif
        return true
    }
}

@main
struct ShuiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var appEnvironment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appEnvironment)
                .shuiTheme()
        }
        .modelContainer(PersistenceController.shared.container)
    }
}
