import UIKit
import CarPlay
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // If the user already granted permission on a previous launch, re-register
        // for remote notifications so the token stays current.
        Task { @MainActor in
            await PushManager.shared.refreshAuthStatus()
            if PushManager.shared.authStatus == .authorized {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == UISceneSession.Role.carTemplateApplication {
            let config = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        return UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    }

    // MARK: - Remote notification registration

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PushManager.shared.onAPNsToken(hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("[push] APNs registration failed: \(error.localizedDescription)")
        Task { @MainActor in PushManager.shared.onAPNsFailure(error.localizedDescription) }
    }
}

// MARK: - Foreground presentation + tap handling

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        return [.banner, .sound, .list]   // show even when the app is foregrounded
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let n = (info["incident"] as? Int) ?? (info["incident"] as? NSNumber)?.intValue {
            await MainActor.run { PushManager.shared.handleTap(incidentNumber: n) }
        }
    }
}
