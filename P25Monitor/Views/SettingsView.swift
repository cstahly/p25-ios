import SwiftUI

struct SettingsView: View {
    let isOnboarding: Bool

    @State private var serverURL = P25Client.shared.baseURL
    @State private var username  = P25Client.shared.username
    @State private var password  = P25Client.shared.password
    @State private var saved     = false
    @EnvironmentObject var store: P25Store

    var body: some View {
        NavigationStack {
            Form {
                if isOnboarding {
                    Section {
                        Text("Enter your p25.sadbabyrabbit.com credentials to connect.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Server") {
                    TextField("URL", text: $serverURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                }

                Section {
                    Button(isOnboarding ? "Connect" : "Save") {
                        P25Client.shared.baseURL  = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        P25Client.shared.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
                        P25Client.shared.password = password
                        store.stop()
                        store.start()
                        saved = true
                    }
                    .disabled(username.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle(isOnboarding ? "Connect" : "Settings")
            .alert("Saved", isPresented: $saved) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}
