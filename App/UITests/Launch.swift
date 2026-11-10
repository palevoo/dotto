import XCTest

extension XCUIApplication {
    /// The app, launched on a notebook of this test's own: new and empty, under the
    /// simulator's temporary directory, gone when the next test starts. What one test writes
    /// is never there for another, and the day a test runs on does not matter. `seeded` adds
    /// the lines, things and marks the tests read; `yesterday` adds that many lines on the
    /// day before today.
    static func onAFreshNotebook(seeded: Bool = false, yesterday: Int = 0) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-uitest-notebook", UUID().uuidString]
        if seeded { arguments.append("-uitest-seed-photos") }
        if yesterday > 0 { arguments += ["-uitest-seed-yesterday", String(yesterday)] }
        app.launchArguments = arguments
        app.launch()
        return app
    }
}
