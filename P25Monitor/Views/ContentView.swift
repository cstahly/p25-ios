import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: P25Store
    @EnvironmentObject var audio: P25AudioPlayer
    var body: some View {
        TabView(selection: $store.selectedTab) {
                MapTabView()
                    .tabItem { Label("Map", systemImage: "map.fill") }
                    .tag(0)

                IncidentListView()
                    .tabItem { Label("Incidents", systemImage: "list.bullet.clipboard") }
                    .tag(1)

                LogView()
                    .tabItem { Label("Log", systemImage: "text.bubble") }
                    .tag(2)

                AudioControlView()
                    .tabItem { Label("Audio", systemImage: "antenna.radiowaves.left.and.right") }
                    .tag(3)

                SettingsView(isOnboarding: false)
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag(4)
        }
        .onAppear { store.start() }
    }
}
