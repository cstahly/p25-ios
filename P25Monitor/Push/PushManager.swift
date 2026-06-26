import Foundation
import UserNotifications
import UIKit

// Mirrors the server's per-device prefs (snake_case on the wire).
struct NotifPrefs: Codable, Equatable {
    var muted: Bool = false
    var minPriority: Int = 1          // 1 = only P1, 2 = P1 + P2
    var agencies: [String] = []       // allowlist; empty = all
    var keywords: [String] = []       // if non-empty, at least one must appear
    var quietStart: String? = nil     // "HH:MM" local, or nil = off
    var quietEnd: String? = nil

    enum CodingKeys: String, CodingKey {
        case muted
        case minPriority = "min_priority"
        case agencies
        case keywords
        case quietStart = "quiet_start"
        case quietEnd = "quiet_end"
    }
}

struct DeviceRegisterResponse: Decodable {
    let prefs: NotifPrefs
    let pushConfigured: Bool?         // present on register + prefs GET

    enum CodingKeys: String, CodingKey {
        case prefs
        case pushConfigured = "push_configured"
    }
}

@MainActor
final class PushManager: ObservableObject {
    static let shared = PushManager()

    @Published var prefs = NotifPrefs()
    @Published var authStatus: UNAuthorizationStatus = .notDetermined
    @Published var serverPushConfigured = false       // false until the .p8 lands server-side
    @Published var lastError: String?
    @Published var registrationError: String?         // APNs didFailToRegister reason, if any

    private let tokenKey = "apnsDeviceTokenHex"
    var deviceToken: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    // Xcode-signed dev builds receive sandbox tokens; a release build would be production.
    var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private init() {}

    /// Pull the current system authorization status into `authStatus`.
    func refreshAuthStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
    }

    /// Learn whether the server has APNs creds, independent of device registration.
    func refreshServerStatus() async {
        serverPushConfigured = await P25Client.shared.fetchPushConfigured()
    }

    /// Ask for permission and, if granted, register for remote notifications.
    /// Returns true if authorized.
    @discardableResult
    func enableNotifications() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthStatus()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Called by AppDelegate once iOS hands us the APNs device token.
    func onAPNsToken(_ hex: String) {
        deviceToken = hex
        registrationError = nil
        Task { await registerWithServer() }
    }

    /// Called by AppDelegate if APNs registration fails (e.g. missing push
    /// entitlement in the provisioning profile).
    func onAPNsFailure(_ message: String) {
        registrationError = message
    }

    /// Re-trigger remote-notification registration (used by the retry button).
    func retryRegistration() {
        registrationError = nil
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Register/refresh the token with the server. Sends prefs=nil so the server
    /// keeps existing prefs for a known token (and applies defaults for a new one)
    /// — this runs on every launch, so it must not clobber the user's settings.
    /// Prefs are edited separately via `savePrefs()`.
    func registerWithServer() async {
        guard let token = deviceToken else { return }
        do {
            let resp = try await P25Client.shared.registerDevice(
                token: token, environment: apnsEnvironment, prefs: nil)
            prefs = resp.prefs
            serverPushConfigured = resp.pushConfigured ?? false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Load this device's prefs from the server (so Settings reflects reality).
    func loadPrefs() async {
        guard let token = deviceToken else { return }
        do {
            let resp = try await P25Client.shared.fetchPrefs(token: token)
            prefs = resp.prefs
            serverPushConfigured = resp.pushConfigured ?? false
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Persist edited prefs to the server.
    func savePrefs() async {
        guard let token = deviceToken else {
            lastError = "Not registered for notifications yet."
            return
        }
        do {
            prefs = try await P25Client.shared.savePrefs(token: token, prefs: prefs)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Trigger a server-side test push to this device.
    func sendTest() async -> Bool {
        guard let token = deviceToken else {
            lastError = "Not registered yet — enable notifications first."
            return false
        }
        do {
            try await P25Client.shared.sendTestPush(token: token)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Route a notification tap to the relevant incident.
    func handleTap(incidentNumber: Int) {
        Task { @MainActor in
            P25Store.shared.focusIncident(number: incidentNumber)
        }
    }
}
