import Core
import Observation
import UIKit
import UserNotifications

/// The phone's side of a push: permission, the address Apple gives this app, and what
/// happens when one is tapped. The address goes into the notebook folder through the model.
@MainActor
@Observable
final class Pushes: NSObject {
    static let shared = Pushes()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    private(set) var token: String?
    /// Apple's refusal to register, in its words.
    private(set) var trouble: String?
    /// Told of a new address, so it can be written where the sender finds it.
    var onToken: ((String) -> Void)?

    var allowed: Bool { status == .authorized || status == .provisional || status == .ephemeral }

    /// Reads where permission stands, and asks Apple for the address again if it is granted:
    /// an address can change between launches.
    func refresh() {
        Task {
            status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if allowed { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Asks once. Refused, the answer lives in Settings.
    func allow() {
        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                trouble = error.localizedDescription
            }
            refresh()
        }
    }

    func took(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        trouble = nil
        onToken?(hex)
    }

    func failed(_ error: Error) {
        trouble = error.localizedDescription
    }
}

/// The app delegate, for the two calls UIKit makes about pushes.
final class PushDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = Taps.shared
        Notices.register()
        Pushes.shared.refresh()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Pushes.shared.took(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Pushes.shared.failed(error)
    }
}

/// A push shown while the app is open, and a push tapped: the line it names opens. A notice
/// about something to do can be answered where it is: Done finishes the line, In an hour
/// says it again then; neither opens the app.
final class Taps: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Taps()

    /// Finishes a line, once there is a notebook open to finish it in.
    @MainActor var onDone: ((ULID) -> Void)? {
        didSet {
            guard let onDone else { return }
            let waiting = finished
            finished = []
            waiting.forEach(onDone)
        }
    }
    /// Lines finished from a notice before the notebook was open.
    @MainActor private var finished: [ULID] = []

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let entry = response.notification.request.content.userInfo["entry"] as? String
        let action = response.actionIdentifier
        let request = response.notification.request
        Task { @MainActor in
            switch action {
            case Notices.doneAction:
                if let id = entry.flatMap({ ULID($0) }) {
                    if let onDone { onDone(id) } else { finished.append(id) }
                }
            case Notices.laterAction:
                Notices.putOff(request)
            default:
                if let entry { Launch.shared.request = .line(entry) }
            }
            completionHandler()
        }
    }
}
