import SwiftUI

@main
struct PourCastApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.settings)
                .environmentObject(app.sites)
                .environmentObject(app.pourStore)
                .environmentObject(app.forecast)
                .tint(.accentTeal)
        }
    }
}
