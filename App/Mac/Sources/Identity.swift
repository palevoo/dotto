import Foundation

/// Which dotto this is. There are two builds of the Mac app: dotto, the home, and dotto dev,
/// for trying a change without touching the home or the notebook it keeps. They differ by
/// bundle id, and everything that must not be shared follows from it here: the door's port,
/// the folder the app keeps its own records in, the keychain entries, the hotkey. Their
/// settings are apart already, since the system keeps those per bundle id.
///
/// dotto dev never runs loops and never carries anything over from the home. It takes its
/// notebook from the folder picked in its own window, or from `-dotto-folder <path>` on its
/// command line, which the home ignores.
enum Identity {
    static let bundleID = Bundle.main.bundleIdentifier ?? "social.interface.margin.mac"
    static let isDevelopment = bundleID.hasSuffix(".dev")

    /// What the app calls itself, in its window, the menu bar and the connect command.
    static let name = isDevelopment ? "dotto dev" : "dotto"
    /// The name of the door as a server, in the command that connects a session to it.
    static let serverName = isDevelopment ? "dotto-dev" : "dotto"
    static let port: UInt16 = isDevelopment ? 27831 : 27830
    /// The folder under Application Support for the app's own records.
    static let supportFolder = isDevelopment ? "Margin Dev" : "Margin"
    /// Only the home runs loops: a second runner on the same notebook would run each twice.
    static let runsLoops = !isDevelopment
    /// Only the home has a past to carry over.
    static let carriesOver = !isDevelopment

    /// A keychain service of this build's own: "<bundle id>.grant-keys".
    static func keychainService(_ what: String) -> String {
        "\(bundleID).\(what)"
    }

    /// The notebook folder named on the command line, for dotto dev only.
    static var folderArgument: URL? {
        guard isDevelopment else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-dotto-folder"), arguments.indices.contains(flag + 1) else { return nil }
        return URL(fileURLWithPath: NSString(string: arguments[flag + 1]).expandingTildeInPath, isDirectory: true)
    }
}
