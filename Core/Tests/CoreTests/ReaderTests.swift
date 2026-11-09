import XCTest
@testable import Core

/// A run is read from the session's stream, line by line.
final class ReaderTests: XCTestCase {
    func testARunFollowsTheStream() {
        var run = ReaderRun(startedAt: Date(timeIntervalSince1970: 0))
        let t = Date(timeIntervalSince1970: 10)
        run.absorb(#"{"type":"system","subtype":"init","model":"claude-sonnet-5-5","tools":[]}"#, at: t)
        run.absorb(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"1","name":"mcp__margin__whats_new","input":{}}]}}"#, at: t)
        run.absorb(#"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"1","content":"1 new thing since 13:00.\n\n## Replies\nwiju under your line: Which pot?"}]}}"#, at: t)
        run.absorb(#"{"type":"assistant","message":{"content":[{"type":"text","text":"One reply asks which pot."},{"type":"tool_use","id":"2","name":"mcp__margin__add_note","input":{"entry":"01M6","text":"The clay one."}}]}}"#, at: t)
        run.absorb(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"2","content":[{"type":"text","text":"Noted under 01M6."}]}]}}"#, at: t)
        run.absorb("not json at all", at: t)
        XCTAssertTrue(run.isRunning)
        XCTAssertEqual(run.model, "claude-sonnet-5-5")
        XCTAssertEqual(run.calls, ["whats_new", "add_note"])
        XCTAssertEqual(run.steps.map(\.what), ["started", "whats_new", "got", "said", "add_note", "got"])
        XCTAssertEqual(run.steps[4].detail, "entry: \u{201C}01M6\u{201D}, text: \u{201C}The clay one.\u{201D}")
        XCTAssertEqual(run.steps[2].detail, "1 new thing since 13:00.  ## Replies wiju under your line: Which pot?")

        run.absorb(#"{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.21,"result":"Done."}"#, at: Date(timeIntervalSince1970: 20))
        XCTAssertFalse(run.isRunning)
        XCTAssertEqual(run.ok, true)
        XCTAssertEqual(run.turns, 3)
        XCTAssertEqual(run.costUSD, 0.21)
        XCTAssertEqual(run.summary, "Done.")
        XCTAssertEqual(run.steps.last?.what, "ended")
    }

    func testAFailedRunKeepsTheReason() {
        var run = ReaderRun()
        run.absorb(#"{"type":"result","subtype":"error_max_budget_usd","is_error":true,"num_turns":4,"total_cost_usd":2.01,"result":"","errors":["Reached maximum budget ($2)"]}"#, at: Date())
        XCTAssertEqual(run.ok, false)
        XCTAssertEqual(run.summary, "Reached maximum budget ($2)")

        var died = ReaderRun()
        died.fail("claude exited 1 with no result", at: Date())
        XCTAssertEqual(died.ok, false)
        XCTAssertEqual(died.steps.map(\.what), ["ended"])
    }

    /// The loop machine: every event in every phase, so the runner has nothing to decide.
    func testTheLoopMachineDecidesEveryStep() {
        var loop = LoopMachine()
        XCTAssertEqual(loop.phase, .idle)

        // A line lands: a look is scheduled. Another lands before the grace: rescheduled.
        XCTAssertEqual(loop.woke(), .scheduleLook)
        XCTAssertEqual(loop.phase, .waking)
        XCTAssertEqual(loop.woke(), .scheduleLook)

        // The look finds nothing: back to idle. Finds something: a run starts.
        XCTAssertEqual(loop.looked(found: false), .nothing)
        XCTAssertEqual(loop.phase, .idle)
        XCTAssertEqual(loop.woke(), .scheduleLook)
        XCTAssertEqual(loop.looked(found: true), .startRun)
        XCTAssertEqual(loop.phase, .running(again: false))
        XCTAssertTrue(loop.isRunning)

        // Lines landing during the run are owed one more look; a late look result changes nothing.
        XCTAssertEqual(loop.woke(), .nothing)
        XCTAssertEqual(loop.looked(found: true), .nothing)
        XCTAssertEqual(loop.phase, .running(again: true))
        XCTAssertEqual(loop.finished(), .lookAgain)
        XCTAssertEqual(loop.phase, .idle)

        // A run that owed nothing ends quietly; finishing when not running is nothing.
        XCTAssertEqual(loop.woke(), .scheduleLook)
        XCTAssertEqual(loop.looked(found: true), .startRun)
        XCTAssertEqual(loop.finished(), .nothing)
        XCTAssertEqual(loop.finished(), .nothing)

        // A forced look, by the clock or by hand, runs at once from idle or waking, and is
        // owed when running.
        XCTAssertEqual(loop.forced(), .startRun)
        XCTAssertEqual(loop.forced(), .nothing)
        XCTAssertEqual(loop.phase, .running(again: true))
        XCTAssertEqual(loop.finished(), .lookAgain)
        XCTAssertEqual(loop.woke(), .scheduleLook)
        XCTAssertEqual(loop.forced(), .startRun)
        XCTAssertEqual(loop.phase, .running(again: false))
    }

    func testRunsAreListedNewestFirst() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("reader-runs-\(ULID().string)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let generator = ULIDGenerator()
        for seconds in [0.0, 60, 120] {
            let run = ReaderRun(id: generator.next(at: Date(timeIntervalSince1970: seconds)), startedAt: Date(timeIntervalSince1970: seconds))
            try JSONLines.encoder().encode(run).write(to: directory.appendingPathComponent("\(run.id.string).json"))
        }
        let runs = ReaderFiles.runs(in: directory, limit: 2)
        XCTAssertEqual(runs.map(\.startedAt.timeIntervalSince1970), [120, 60])
    }
}
