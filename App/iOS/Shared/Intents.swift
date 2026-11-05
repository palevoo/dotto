import AppIntents
import Foundation
import Observation

/// What a press from outside the app asked for, held until the page is up to do it.
/// Compiled into the app and into the controls extension.
@MainActor
@Observable
final class Launch {
    static let shared = Launch()

    enum Request: Equatable {
        case write
        case photo
        case speak
        /// A push was tapped: open this line, by its id.
        case line(String)
    }

    var request: Request?
}

/// One press: the page, with the line ready and the keyboard up.
struct WriteIntent: AppIntent {
    static let title: LocalizedStringResource = "Write"
    static let description = IntentDescription("Opens Margin with the line ready.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Launch.shared.request = .write
        return .result()
    }
}

/// One press: recording starts; the words land in the line when you stop.
struct SpeakIntent: AppIntent {
    static let title: LocalizedStringResource = "Speak"
    static let description = IntentDescription("Opens Margin and starts listening.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Launch.shared.request = .speak
        return .result()
    }
}

/// One press: straight into the camera; the photo lands in the line.
struct PhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Photo"
    static let description = IntentDescription("Opens Margin's camera.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Launch.shared.request = .photo
        return .result()
    }
}
