import SwiftUI
import SwiftData

@main
struct HistudyApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
        .modelContainer(PersistenceController.shared.container)
    }
}
