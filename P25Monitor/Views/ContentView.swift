import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: P25Store
    @EnvironmentObject var audio: P25AudioPlayer
    @State private var showSettings = false
    @AppStorage("username") private var username = ""

    var body: some View {
        if username.isEmpty {
            SettingsView(isOnboarding: true)
        } else {
            TabView {
                MapTabView()
                    .tabItem { Label("Map", systemImage: "map.fill") }

                IncidentListView()
                    .tabItem { Label("Incidents", systemImage: "list.bullet.clipboard") }

                AudioControlView()
                    .tabItem { Label("Audio", systemImage: "antenna.radiowaves.left.and.right") }

                SettingsView(isOnboarding: false)
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
            .onAppear { store.start() }
        }
    }
}
