import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: P25Store
    @EnvironmentObject var audio: P25AudioPlayer
    var body: some View {
        TabView {
                MapTabView()
                    .tabItem { Label("Map", systemImage: "map.fill") }

                IncidentListView()
                    .tabItem { Label("Incidents", systemImage: "list.bullet.clipboard") }

                LogView()
                    .tabItem { Label("Log", systemImage: "text.bubble") }

                AudioControlView()
                    .tabItem { Label("Audio", systemImage: "antenna.radiowaves.left.and.right") }

                SettingsView(isOnboarding: false)
                    .tabItem { Label("Settings", systemImage: "gear") }
        }
        .onAppear { store.start() }
    }
}
