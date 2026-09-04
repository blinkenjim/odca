import Foundation
import XCTest

@testable import ODCAKit

/// Layer 2 of TESTS.md: session properties PT-9, PT-10, PT-10a, PT-13, PT-14.
/// All file access goes to a temp Store; the search is never started.
final class SessionTests: XCTestCase {
    func makeStore(saved: [Rule] = [], currentRule: Rule? = nil) throws -> Store {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odca-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store(
            stateDir: dir.appendingPathComponent("state"),
            keeperFile: dir.appendingPathComponent("interesting-rules.txt"))
        for rule in saved { store.appendInteresting(rule) }
        if let rule = currentRule { store.saveRule(rule) }
        return store
    }

    func makeSession(_ store: Store, seed: UInt64 = 1) -> Session {
        Session(cols: 32, rows: 16, store: store,
                search: CandidateSearch(workers: 0), rng: Xoshiro256(seed: seed))
    }

    var fourSaved: [Rule] {
        ["0", "1", "2", "3"].map { try! Rule(id: String(repeating: $0, count: 20)) }
    }

    // PT-9: undo restores LIFO; empty stack is a no-op.
    func testUndoLIFO() throws {
        let session = makeSession(try makeStore())
        let r0 = session.automaton.rule
        XCTAssertTrue(session.handleKey(.m))
        let r1 = session.automaton.rule
        XCTAssertTrue(session.handleKey(.m))
        XCTAssertTrue(session.handleKey(.u))
        XCTAssertEqual(session.automaton.rule, r1)
        XCTAssertTrue(session.handleKey(.u))
        XCTAssertEqual(session.automaton.rule, r0)
        XCTAssertTrue(session.handleKey(.u))  // empty stack: no-op
        XCTAssertEqual(session.automaton.rule, r0)
    }

    // PT-10: startup rule not saved -> unsaved-slot cycle semantics.
    func testCycleWithUnsavedSlot() throws {
        let saved = fourSaved
        let outside = try Rule(id: "01230123012301230123")
        let session = makeSession(try makeStore(saved: saved, currentRule: outside))
        XCTAssertNil(session.interestingIndex)
        XCTAssertEqual(session.unsavedRule, outside)

        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])  // first n -> 0
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, outside)  // back to unsaved
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, saved[3])  // p wraps to n-1
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, outside)  // past last -> unsaved

        session.handleKey(.m)  // new rule occupies the unsaved slot
        let mutant = session.automaton.rule
        XCTAssertNil(session.interestingIndex)
        XCTAssertEqual(session.unsavedRule, mutant)
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, mutant)
    }

    // PT-10a: startup rule equals saved rule j -> cycle starts there,
    // no unsaved slot until r/m.
    func testCycleStartupMatch() throws {
        let saved = fourSaved
        let session = makeSession(try makeStore(saved: saved, currentRule: saved[2]))
        XCTAssertEqual(session.interestingIndex, 2)
        XCTAssertNil(session.unsavedRule)

        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[3])
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])  // wraps with no unsaved stop
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, saved[3])

        session.handleKey(.m)
        let mutant = session.automaton.rule
        XCTAssertEqual(session.unsavedRule, mutant)
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, mutant)
    }

    // Empty keeper file: n/p change nothing (R-B4).
    func testCycleEmptyKeeper() throws {
        let session = makeSession(try makeStore())
        let rule = session.automaton.rule
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, rule)
        XCTAssertNil(session.interestingIndex)
    }

    // PT-13: while paused, every key but space/Return/q is a no-op.
    func testPauseModality() throws {
        let session = makeSession(try makeStore(saved: fourSaved))
        XCTAssertTrue(session.handleKey(.space))
        XCTAssertTrue(session.paused)
        let rule = session.automaton.rule
        let cells = session.automaton.cells
        let delay = session.delay
        let colorSet = session.colorSet
        let index = session.interestingIndex
        for key: Session.Key in [.r, .m, .u, .s, .i, .n, .p, .plus, .minus, .digit(1)] {
            XCTAssertTrue(session.handleKey(key))
        }
        XCTAssertEqual(session.automaton.rule, rule)
        XCTAssertEqual(session.automaton.cells, cells)
        XCTAssertEqual(session.delay, delay)
        XCTAssertEqual(session.colorSet, colorSet)
        XCTAssertEqual(session.interestingIndex, index)

        XCTAssertTrue(session.handleKey(.space))  // resume
        XCTAssertFalse(session.paused)
        XCTAssertTrue(session.handleKey(.digit(1)))
        XCTAssertEqual(session.colorSet, 1)  // keys live again

        XCTAssertTrue(session.handleKey(.space))
        XCTAssertFalse(session.handleKey(.q))  // q still quits while paused
    }

    // PT-14: Return single-steps while paused; ignored when running.
    func testSingleStep() throws {
        let session = makeSession(try makeStore())
        let g0 = session.automaton.generation
        XCTAssertTrue(session.handleKey(.ret))  // not paused: ignored
        XCTAssertEqual(session.automaton.generation, g0)

        XCTAssertTrue(session.handleKey(.space))
        for i in 1...3 {
            XCTAssertTrue(session.handleKey(.ret))
            XCTAssertEqual(session.automaton.generation, g0 + i)
            XCTAssertTrue(session.paused)
        }
    }

    // R-K8: delay halves/doubles within clamps; R-U5 pause discards time.
    func testSpeedAndTick() throws {
        let session = makeSession(try makeStore())
        XCTAssertEqual(session.delay, Session.initialDelay)
        for _ in 0..<50 { _ = session.handleKey(.plus) }
        XCTAssertEqual(session.delay, Session.minDelay)
        for _ in 0..<50 { _ = session.handleKey(.minus) }
        XCTAssertEqual(session.delay, Session.maxDelay)

        let session2 = makeSession(try makeStore())
        let g0 = session2.automaton.generation
        session2.tick(1.0)  // 1 s at 60 gen/s
        XCTAssertEqual(session2.automaton.generation, g0 + 60)
        _ = session2.handleKey(.space)
        session2.tick(5.0)  // paused: time discarded
        _ = session2.handleKey(.space)
        session2.tick(0.0)
        XCTAssertEqual(session2.automaton.generation, g0 + 60)
    }
}
