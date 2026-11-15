import Foundation

/// Which build is running: the commit it was made from, which `App/Scripts/stamp.sh` says
/// and Xcode puts into the app's Info.plist as it makes it. Compare it with `git log` to see
/// whether the app on the device is the one in the repository. Nil outside a stamped app.
public enum Build {
    /// Short commit hash, with a trailing "+" when the tree had uncommitted changes.
    public static let commit: String? = commit(in: Bundle.main.infoDictionary ?? [:])

    /// When that commit was made. The build number is that moment, to the minute.
    public static let committedAt: Date? = moment(of: Bundle.main.infoDictionary?["CFBundleVersion"] as? String)

    /// "Build a1b2c3d · 5 Nov 18:20", the commit and when it was made, or nil when not stamped.
    public static func label(calendar: Calendar = .current) -> String? {
        guard let commit else { return nil }
        var text = "Build \(commit)"
        if let committedAt {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
            text += " · \(formatter.string(from: committedAt))"
        }
        return text
    }

    /// The commit as an Info.plist says it: `DottoCommit`, and `DottoChanged` yes or no.
    static func commit(in info: [String: Any]) -> String? {
        guard let commit = info["DottoCommit"] as? String, !commit.isEmpty else { return nil }
        return (info["DottoChanged"] as? String) == "yes" ? commit + "+" : commit
    }

    /// The moment a build number names: twelve digits, year to minute, in UTC. Nil for a
    /// number that is not one, as a build made outside a git checkout has.
    static func moment(of number: String?) -> Date? {
        guard let number, number.count == 12, number.allSatisfy(\.isNumber) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter.date(from: number)
    }
}
