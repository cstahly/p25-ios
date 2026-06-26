import SwiftUI
import UIKit
import UserNotifications

struct NotificationSettingsView: View {
    @EnvironmentObject var push: PushManager
    @EnvironmentObject var store: P25Store

    @State private var keywordText = ""
    @State private var quietOn = false
    @State private var quietStart = Date()
    @State private var quietEnd = Date()
    @State private var saving = false
    @State private var testResult: String?

    var body: some View {
        Form {
            switch push.authStatus {
            case .denied:
                Section {
                    Text("Notifications are turned off for P25Monitor in iOS Settings.")
                        .foregroundColor(.secondary)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            case .authorized, .provisional, .ephemeral:
                rulesSections
            default:
                Section {
                    Text("Get a push when a high-priority incident hits the board.")
                        .foregroundColor(.secondary)
                    Button("Enable notifications") {
                        Task { await push.enableNotifications() }
                    }
                }
            }

            if !push.serverPushConfigured {
                Section {
                    Label("Push isn't enabled on the server yet (awaiting the APNs key). "
                          + "Your settings are saved and will take effect once it is.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if let err = push.lastError {
                Section { Text(err).font(.footnote).foregroundColor(.red) }
            }
        }
        .navigationTitle("Notifications")
        .onAppear(perform: loadFromPrefs)
        .task { await push.loadPrefs(); loadFromPrefs(); await push.refreshAuthStatus() }
    }

    @ViewBuilder
    private var rulesSections: some View {
        Section {
            Toggle("Mute all notifications", isOn: $push.prefs.muted)
        } footer: {
            Text("Stay registered but silence everything. Un-mute to resume.")
        }

        Section("Priority") {
            Picker("Notify me about", selection: $push.prefs.minPriority) {
                Text("P1 only").tag(1)
                Text("P1 and P2").tag(2)
            }
            .pickerStyle(.segmented)
        }

        Section {
            NavigationLink {
                AgencyAllowlistView(selected: $push.prefs.agencies,
                                    available: store.availableAgencies)
            } label: {
                HStack {
                    Text("Agencies")
                    Spacer()
                    Text(push.prefs.agencies.isEmpty ? "All" : "\(push.prefs.agencies.count) selected")
                        .foregroundColor(.secondary)
                }
            }
        } footer: {
            Text("Limit notifications to specific agencies. Default: all.")
        }

        Section("Keywords") {
            TextField("e.g. fire, pursuit, shots", text: $keywordText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }

        Section("Quiet hours") {
            Toggle("Silence overnight", isOn: $quietOn)
            if quietOn {
                DatePicker("Start", selection: $quietStart, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $quietEnd, displayedComponents: .hourAndMinute)
            }
        }

        Section {
            Button {
                Task { await save() }
            } label: {
                HStack { Text("Save"); if saving { Spacer(); ProgressView() } }
            }
            .disabled(saving)

            Button("Send test notification") {
                Task {
                    let ok = await push.sendTest()
                    testResult = ok ? "Sent — check your lock screen." : (push.lastError ?? "Failed.")
                }
            }
            if let testResult {
                Text(testResult).font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - prefs <-> UI

    private func loadFromPrefs() {
        keywordText = push.prefs.keywords.joined(separator: ", ")
        if let s = push.prefs.quietStart, let e = push.prefs.quietEnd {
            quietOn = true
            quietStart = Self.dateFrom(hhmm: s) ?? quietStart
            quietEnd = Self.dateFrom(hhmm: e) ?? quietEnd
        } else {
            quietOn = false
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        push.prefs.keywords = keywordText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        push.prefs.quietStart = quietOn ? Self.hhmm(from: quietStart) : nil
        push.prefs.quietEnd   = quietOn ? Self.hhmm(from: quietEnd)   : nil
        await push.savePrefs()
    }

    private static func hhmm(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func dateFrom(hhmm: String) -> Date? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())
    }
}

/// Multi-select agency allowlist. Empty selection == all agencies.
struct AgencyAllowlistView: View {
    @Binding var selected: [String]
    let available: [String]

    var body: some View {
        List {
            Section {
                Button("Clear (notify for all agencies)") { selected = [] }
                    .disabled(selected.isEmpty)
            }
            Section("Agencies") {
                ForEach(available, id: \.self) { agency in
                    Button {
                        if let i = selected.firstIndex(of: agency) { selected.remove(at: i) }
                        else { selected.append(agency) }
                    } label: {
                        HStack {
                            Text(agency).foregroundColor(.primary)
                            Spacer()
                            if selected.contains(agency) {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                    }
                }
                if available.isEmpty {
                    Text("No agencies seen yet — open the Incidents tab to populate this list.")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Agencies")
    }
}
