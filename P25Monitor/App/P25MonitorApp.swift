import SwiftUI

@main
struct P25MonitorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(P25Store.shared)
                .environmentObject(P25AudioPlayer.shared)
                .environmentObject(PushManager.shared)
        }
    }
}
