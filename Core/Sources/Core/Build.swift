import Foundation

/// Which build is running: the commit it was made from, stamped into the app's Info.plist
/// by `App/Scripts/stamp.sh` at build time. Compare it with `git log` to see whether the
/// app on the device is the one in the repository. Nil outside a stamped app.
public enum Build {
    /// Short commit hash, with a trailing "+" when the tree had uncommitted changes.
    public static let commit: String? = Bundle.main.infoDictionary?["MarginCommit"] as? String

    public static let builtAt: Date? = (Bundle.main.infoDictionary?["MarginBuiltAt"] as? String).flatMap {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: $0)
    }

    /// "Build a1b2c3d · 5 Nov 18:20", or nil when not stamped.
    public static func label(calendar: Calendar = .current) -> String? {
        guard let commit else { return nil }
        var text = "Build \(commit)"
        if let builtAt {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
            text += " · \(formatter.string(from: builtAt))"
        }
        return text
    }
}
