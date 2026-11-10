import Core
import UserNotifications

/// What the phone says by itself about what is coming. The notices are worked out from the
/// fold (`Notebook.notices`) and handed to the system here, so they fire with no network,
/// no Mac and the app not running. Asked again every time the notebook is read: what is no
/// longer wanted, a moment moved, taken off or finished, is withdrawn, and what is new is
/// added. Nothing is kept here; the system's own list of what is waiting is the state.
enum Notices {
    /// The buttons on a notice about something to do.
    static let todoCategory = "todo"
    static let doneAction = "done"
    static let laterAction = "later"
    /// How long Later puts a notice off.
    static let later: TimeInterval = 3600

    private static let prefix = "notice|"
    private static let laterPrefix = "later|"

    /// Told to the system once, at launch: something to do can be finished, or put off an
    /// hour, from the notice itself, without opening the app.
    static func register() {
        let done = UNNotificationAction(identifier: doneAction, title: "Done", options: [])
        let later = UNNotificationAction(identifier: laterAction, title: "In an hour", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: todoCategory, actions: [done, later], intentIdentifiers: []),
        ])
    }

    /// Makes what is waiting in the system match `wanted`. `open` is every line not done, so
    /// a notice put off with Later is withdrawn once its line is finished or gone. False
    /// when notices are not allowed, and nothing was set.
    static func sync(_ wanted: [Notice], open: Set<ULID>, calendar: Calendar) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return false }
        let waiting = await center.pendingNotificationRequests()
        let wantedIDs = Set(wanted.map(\.id))
        var gone = waiting.map(\.identifier).filter { $0.hasPrefix(prefix) && !wantedIDs.contains($0) }
        gone += waiting.filter { $0.identifier.hasPrefix(laterPrefix) }
            .filter { request in
                guard let id = (request.content.userInfo["entry"] as? String).flatMap({ ULID($0) }) else { return true }
                return !open.contains(id)
            }
            .map(\.identifier)
        if !gone.isEmpty { center.removePendingNotificationRequests(withIdentifiers: gone) }
        let have = Set(waiting.map(\.identifier))
        for notice in wanted where !have.contains(notice.id) {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            content.userInfo = ["entry": notice.entry.string]
            if notice.todo { content.categoryIdentifier = todoCategory }
            // By the date on the wall, so a change of clock or zone moves it with the day.
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notice.fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger))
        }
        return true
    }

    /// Later, pressed on a notice: the same words again in an hour.
    static func putOff(_ request: UNNotificationRequest) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: later, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: laterPrefix + UUID().uuidString, content: content, trigger: trigger))
    }
}
