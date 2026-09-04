import Foundation
import XCTest

@testable import ODCAKit

/// Layer 2 of TESTS.md: session properties PT-9, PT-10, PT-10a, PT-13..PT-24.
/// All file access goes to a temp Store; the search is never started.
final class SessionTests: XCTestCase {
    func makeStore(saved: [Rule] = [], currentRule: Rule? = nil) throws -> Store {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odca-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store(
            stateDir: dir.appendingPathComponent("state"),
            keeperFile: dir.appendingPathComponent("interesting-rules.txt"),
            colorSetsFile: dir.appendingPathComponent("colorsets.json"),
            candidatePalettesFile: dir.appendingPathComponent("candidates.json"))
        for rule in saved { store.appendInteresting(rule) }
        if let rule = currentRule { store.saveRule(rule) }
        return store
    }

    /// A session whose terminal output is captured into `lines`.
    func makeSession(_ store: Store, seed: UInt64 = 1, lines: Lines? = nil,
                     review: Bool = false, screensaver: URL? = nil, grouped: Bool = false) -> Session {
        let sink: (String) -> Void = lines.map { l in { l.all.append($0) } } ?? { print($0) }
        return Session(cols: 32, rows: 16, store: store,
                       search: CandidateSearch(workers: 0), rng: Xoshiro256(seed: seed),
                       reviewMode: review, screensaverFile: screensaver, groupByRule: grouped,
                       output: sink)
    }

    final class Lines { var all: [String] = []; func take() -> String { defer { all.removeAll() }; return all.joined(separator: "\n") } }

    var fourSaved: [Rule] {
        ["0", "1", "2", "3"].map { try! Rule(id: String(repeating: $0, count: 20)) }
    }
    let allZero = try! Rule(id: String(repeating: "0", count: 20))
    let allProducible = try! Rule(id: String(repeating: "0123", count: 5))
    // Every neighborhood -> 1 except three 3s -> 3: 3 is producible but dies out.
    let killsThree = try! Rule(states: [3] + [UInt8](repeating: 1, count: 19))

    /// n distinct random rows, each containing all four states.
    func distinctRows(_ n: Int, seed: UInt64) -> [[UInt8]] {
        var rng = Xoshiro256(seed: seed)
        var rows: [[UInt8]] = []
        var seen = Set<[UInt8]>()
        while rows.count < n {
            var row = Automaton.randomCells(width: 32, using: &rng)
            row[0] = 0; row[1] = 1; row[2] = 2; row[3] = 3
            if seen.insert(row).inserted { rows.append(row) }
        }
        return rows
    }

    // MARK: PT-9, PT-10, PT-10a

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

    func testCycleWithUnsavedSlot() throws {
        let saved = fourSaved
        let outside = try Rule(id: "01230123012301230123")
        let session = makeSession(try makeStore(saved: saved, currentRule: outside))
        XCTAssertNil(session.interestingIndex)
        XCTAssertEqual(session.unsavedRule, outside)
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, outside)
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, saved[3])
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, outside)
        _ = session.handleKey(.m)
        let mutant = session.automaton.rule
        XCTAssertNil(session.interestingIndex)
        XCTAssertEqual(session.unsavedRule, mutant)
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, mutant)
    }

    func testCycleStartupMatch() throws {
        let saved = fourSaved
        let session = makeSession(try makeStore(saved: saved, currentRule: saved[2]))
        XCTAssertEqual(session.interestingIndex, 2)
        XCTAssertNil(session.unsavedRule)
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[3])
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, saved[3])
        _ = session.handleKey(.m)
        let mutant = session.automaton.rule
        XCTAssertEqual(session.unsavedRule, mutant)
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, mutant)
    }

    func testCycleEmptyKeeper() throws {
        let session = makeSession(try makeStore())
        let rule = session.automaton.rule
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, rule)
        XCTAssertNil(session.interestingIndex)
    }

    // MARK: PT-13, PT-14

    func testPauseModality() throws {
        let store = try makeStore(saved: fourSaved)
        let session = makeSession(store)
        XCTAssertTrue(session.handleKey(.space))
        XCTAssertTrue(session.paused)
        let rule = session.automaton.rule
        let cells = session.automaton.cells
        let delay = session.delay
        let index = session.interestingIndex
        for key: Session.Key in [.r, .m, .u, .i, .n, .p, .a, .plus, .minus] {
            XCTAssertTrue(session.handleKey(key))
        }
        XCTAssertEqual(session.automaton.rule, rule)
        XCTAssertEqual(session.automaton.cells, cells)
        XCTAssertEqual(session.delay, delay)
        XCTAssertEqual(session.interestingIndex, index)
        XCTAssertTrue(session.autoInit)  // 'a' is ignored while paused
        _ = session.handleKey(.digit(7))  // undefined slot: still a no-op while paused
        XCTAssertEqual(session.colorSet, 1)
        let palette = session.palette
        _ = session.handleKey(.c)  // colors are live while paused (R-K10)
        XCTAssertNotEqual(session.palette, palette)
        _ = session.handleKey(.S)
        XCTAssertEqual(store.loadColorSets()[1]!.colors[2], "#409CFF")  // saved the arrangement

        XCTAssertTrue(session.handleKey(.space))  // resume
        XCTAssertFalse(session.paused)
        _ = session.handleKey(.plus)
        XCTAssertEqual(session.delay, delay / 2)  // keys live again
        XCTAssertTrue(session.handleKey(.space))
        XCTAssertFalse(session.handleKey(.q))  // q still quits while paused
    }

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

    func testSpeedAndTick() throws {
        let session = makeSession(try makeStore())
        XCTAssertEqual(session.delay, Session.initialDelay)
        for _ in 0..<50 { _ = session.handleKey(.plus) }
        XCTAssertEqual(session.delay, Session.minDelay)
        for _ in 0..<50 { _ = session.handleKey(.minus) }
        XCTAssertEqual(session.delay, Session.maxDelay)

        let session2 = makeSession(try makeStore())
        _ = session2.handleKey(.a)  // pacing test: keep auto-init from re-seeding mid-run
        let g0 = session2.automaton.generation
        session2.tick(1.0)
        XCTAssertEqual(session2.automaton.generation, g0 + 60)
        _ = session2.handleKey(.space)
        session2.tick(5.0)  // paused: time discarded
        _ = session2.handleKey(.space)
        session2.tick(0.0)  // resume computes exactly one generation, seamlessly (R-K10)
        XCTAssertEqual(session2.automaton.generation, g0 + 61)
        session2.tick(0.0)
        XCTAssertEqual(session2.automaton.generation, g0 + 61)
    }

    // MARK: PT-15..PT-17 auto-init

    func testAutoInitFiresWhenScreenIsBoring() throws {
        let lines = Lines()
        let session = makeSession(try makeStore(currentRule: allZero), lines: lines)
        XCTAssertTrue(session.autoInit)  // on at startup (R-K12)
        _ = lines.take()
        for _ in 0..<16 { session.tick(1.0 / 60.0) }
        XCTAssertEqual(session.automaton.generation, 16)
        session.tick(1.0 / 60.0)
        XCTAssertEqual(session.automaton.generation, 0)  // re-initialized on the 17th
        XCTAssertTrue(lines.take().contains("auto-init (repeating (period 1))"))
        XCTAssertEqual(session.automaton.rule, allZero)
    }

    func testAutoInitOffDoesNothing() throws {
        let lines = Lines()
        let session = makeSession(try makeStore(currentRule: allZero), lines: lines)
        _ = session.handleKey(.a)  // turn the mode off
        XCTAssertFalse(session.autoInit)
        XCTAssertTrue(lines.take().contains("auto-init off"))
        for _ in 0..<40 { session.tick(1.0 / 60.0) }
        XCTAssertEqual(session.automaton.generation, 40)
        XCTAssertFalse(lines.take().contains("auto-init ("))
    }

    func testAutoInitReportsExtinction() throws {
        let lines = Lines()
        let session = makeSession(try makeStore(currentRule: killsThree), lines: lines)
        var fired = false
        for _ in 0..<200 {
            let before = session.automaton.generation
            session.tick(1.0 / 60.0)
            if session.automaton.generation < before { fired = true; break }
        }
        XCTAssertTrue(fired)
        XCTAssertTrue(lines.take().contains("auto-init (state 3 extinct)"))
    }

    func testBoringCountResetsOnRuleChangeAndToggle() throws {
        let lines = Lines()
        let session = makeSession(try makeStore(currentRule: allZero), lines: lines)
        for _ in 0..<10 { session.tick(1.0 / 60.0) }
        XCTAssertGreaterThan(session.boringStreak, 0)
        _ = session.handleKey(.m)
        XCTAssertEqual(session.boringStreak, 0)
        _ = session.handleKey(.a)
        _ = session.handleKey(.a)
        let out = lines.all
        XCTAssertEqual(out.suffix(2), ["auto-init off", "auto-init on"])
        XCTAssertTrue(session.autoInit)
    }

    func testAutoInitViaSingleStepWhilePaused() throws {
        let lines = Lines()
        let session = makeSession(try makeStore(currentRule: allZero), lines: lines)
        _ = session.handleKey(.space)
        for _ in 0..<17 { _ = session.handleKey(.ret) }
        XCTAssertEqual(session.automaton.generation, 0)
        XCTAssertTrue(session.paused)
        XCTAssertTrue(lines.take().contains("auto-init (repeating (period 1))"))
    }

    // MARK: PT-16a, PT-18, PT-21, PT-22 detectors

    func testExtinctionWaitsForLivingMinority() throws {
        let session = makeSession(try makeStore(currentRule: allProducible))
        let two = [UInt8](repeating: 0, count: 32).enumerated().map { UInt8($0.offset % 2 + 2) }
        session.observe(two)
        XCTAssertEqual(session.boringStreak, 1)
        XCTAssertEqual(session.boringReason, "states 0, 1 extinct")
        var lone = two; lone[5] = 1  // one cell of state 1: a living minority
        let s2 = makeSession(try makeStore(currentRule: allProducible))
        s2.observe(lone)
        XCTAssertEqual(s2.boringStreak, 0)
        XCTAssertNil(s2.boringReason)
        var many = two; for i in 0..<7 { many[i] = 1 }  // 22%: a real population
        let s3 = makeSession(try makeStore(currentRule: allProducible))
        s3.observe(many)
        XCTAssertEqual(s3.boringStreak, 1)
        XCTAssertEqual(s3.boringReason, "state 0 extinct")
    }

    func testStagnantMinorityAfterFourScreens() throws {
        let session = makeSession(try makeStore(currentRule: allProducible))
        var rng = Xoshiro256(seed: 3)
        let window = Session.stagnationScreens * session.rows
        func row(minority count: Int) -> [UInt8] {
            var r = (0..<32).map { _ in UInt8.random(in: 2...3, using: &rng) }
            var positions = Array(0..<32).shuffled(using: &rng)
            for _ in 0..<count { r[positions.removeLast()] = 1 }
            return r
        }
        for _ in 0..<(window - 1) { session.observe(row(minority: 2)) }
        XCTAssertEqual(session.boringStreak, 0)
        for _ in 0..<7 { session.observe(row(minority: 2)) }
        XCTAssertEqual(session.boringStreak, 7)
        XCTAssertEqual(session.boringReason, "stagnant")

        let s2 = makeSession(try makeStore(currentRule: allProducible))
        for g in 0..<(window + 20) {  // 1 and 3 cells: both minorities, swing 1.0
            s2.observe(row(minority: g % 2 == 0 ? 1 : 3))
            XCTAssertEqual(s2.boringStreak, 0)
        }
    }

    func testRepetitionWindowSpansTenScreens() throws {
        let session = makeSession(try makeStore(currentRule: allProducible))
        let rows = distinctRows(Session.repeatScreens * session.rows + 1, seed: 9)
        for row in rows.dropLast() { session.observe(row) }
        XCTAssertEqual(session.boringStreak, 0)
        session.observe(rows[0])  // exactly ten screens later: still in window
        XCTAssertEqual(session.boringStreak, 1)
        XCTAssertEqual(session.boringReason, "repeating")

        let s2 = makeSession(try makeStore(currentRule: allProducible))
        for row in rows { s2.observe(row) }  // one extra row pushes rows[0] out
        s2.observe(rows[0])
        XCTAssertEqual(s2.boringStreak, 0)
    }

    func testBrentFindsPeriodBeyondTheWindow() throws {
        let lines = Lines()
        let session = makeSession(try makeStore(currentRule: allProducible), lines: lines)
        let period = 3 * Session.repeatScreens * session.rows
        let all = distinctRows(37 + period, seed: 12)
        let transient = Array(all[0..<37]), cycle = Array(all[37...])
        for row in transient { session.observe(row) }
        var g = 0
        while session.cyclePeriod == nil && g < 10 * period {
            session.observe(cycle[g % period]); g += 1
        }
        XCTAssertEqual(session.cyclePeriod, period)
        XCTAssertTrue(lines.take().contains("cycle period \(period)"))
        XCTAssertEqual(session.boringReason, "repeating (period \(period))")
        _ = session.handleKey(.m)  // rule change resets the detector
        XCTAssertNil(session.cyclePeriod)

        let s2 = makeSession(try makeStore(currentRule: allProducible))
        let seven = distinctRows(7, seed: 13)
        for g in 0..<200 { s2.observe(seven[g % 7]) }
        XCTAssertEqual(s2.cyclePeriod, 7)
    }

    // MARK: PT-19, PT-20 paused 's' and the screen counter

    func testPausedSZipsOneScreenful() throws {
        let session = makeSession(try makeStore())
        _ = session.handleKey(.space)
        let g0 = session.automaton.generation
        _ = session.handleKey(.s)
        XCTAssertEqual(session.screenRemaining, session.rows)
        let fast = session.delay / Session.screenSpeedup
        session.tick(fast * 4.5)  // 4 generations at one eighth the delay
        XCTAssertEqual(session.automaton.generation, g0 + 4)
        session.tick(10.0)  // only the rest of the screenful runs
        XCTAssertEqual(session.automaton.generation, g0 + session.rows)
        XCTAssertEqual(session.screenRemaining, 0)
        XCTAssertTrue(session.paused)
        session.tick(10.0)
        XCTAssertEqual(session.automaton.generation, g0 + session.rows)

        _ = session.handleKey(.s)
        _ = session.handleKey(.s)
        XCTAssertEqual(session.screenRemaining, 2 * session.rows)
        _ = session.handleKey(.space)  // resume cancels the queue
        XCTAssertEqual(session.screenRemaining, 0)
        _ = session.handleKey(.s)  // unpaused: saves, does not queue
        XCTAssertEqual(session.screenRemaining, 0)
        XCTAssertEqual(session.store.loadInteresting(), [session.automaton.rule])
    }

    func testScreenCounterRunsFromResume() throws {
        let lines = Lines()
        let session = makeSession(try makeStore(), lines: lines)
        session.tick(100.0)
        XCTAssertNil(session.screenCounter)
        XCTAssertFalse(lines.take().contains("screen "))
        _ = session.handleKey(.space)
        _ = session.handleKey(.space)
        XCTAssertEqual(session.screenCounter, 0)
        session.tick(0.0)  // the seamless-resume generation (R-K10)
        session.tick(session.delay * Double(session.rows - 2))
        XCTAssertEqual(session.screenCounter, 0)
        session.tick(session.delay * 1.5)
        XCTAssertEqual(session.screenCounter, 1)
        XCTAssertTrue(lines.take().contains("screen 1"))
        _ = session.handleKey(.space)  // pause: counter keeps counting
        _ = session.handleKey(.s)
        session.tick(100.0)
        XCTAssertEqual(session.screenCounter, 2)
        for _ in 0..<session.rows { _ = session.handleKey(.ret) }
        XCTAssertEqual(session.screenCounter, 3)
        _ = session.handleKey(.space)  // resume restarts from 0
        XCTAssertEqual(session.screenCounter, 0)
    }

    // MARK: PT-23, PT-24 color sets

    func testDefaultOnlyWithoutColorSetsFile() throws {
        let session = makeSession(try makeStore())
        XCTAssertEqual(session.colorSet, 1)
        XCTAssertEqual(Set(session.colorSets.keys), [1])
        XCTAssertEqual(session.palette, [RGB(r: 0x12, g: 0x12, b: 0x18), RGB(r: 0xEB, g: 0xEB, b: 0xE1),
                                         RGB(r: 0xFF, g: 0xA1, b: 0x36), RGB(r: 0x40, g: 0x9C, b: 0xFF)])
        _ = session.handleKey(.digit(7))
        XCTAssertEqual(session.colorSet, 1)
    }

    func testColorSetsLoadFromFile() throws {
        let store = try makeStore()
        store.saveColorSets([0: ColorSet(name: "Zero", colors: ["#000000", "#111111", "#222222", "#333333"]),
                             5: ColorSet(name: "Five", colors: ["#AAAAAA", "#BBBBBB", "#CCCCCC", "#DDDDDD"])])
        let session = makeSession(store)
        XCTAssertEqual(Set(session.colorSets.keys), [0, 1, 5])
        for d in 0...9 {
            let before = session.colorSet
            _ = session.handleKey(.digit(d))
            XCTAssertEqual(session.colorSet, [0, 1, 5].contains(d) ? d : before)
        }
        _ = session.handleKey(.digit(5))
        XCTAssertEqual(session.palette[0], RGB(r: 0xAA, g: 0xAA, b: 0xAA))
    }

    func testCycleArrangementsAndSave() throws {
        let lines = Lines()
        let store = try makeStore()
        store.saveColorSets([3: ColorSet(name: "Three", colors: ["#000000", "#111111", "#222222", "#333333"])])
        let session = makeSession(store, lines: lines)
        _ = session.handleKey(.digit(3))
        XCTAssertEqual(Session.arrangements.count, 24)
        XCTAssertEqual(Session.arrangements[0], [0, 1, 2, 3])
        _ = session.handleKey(.c)
        XCTAssertEqual(session.palette.map(\.r), [0x00, 0x11, 0x33, 0x22])  // (0,1,3,2)
        XCTAssertTrue(lines.take().contains("color set 3 arrangement 2/24"))
        for _ in 0..<23 { _ = session.handleKey(.c) }
        XCTAssertEqual(session.palette.map(\.r), [0x00, 0x11, 0x22, 0x33])  // wrapped
        _ = session.handleKey(.c)
        _ = session.handleKey(.digit(1))  // arrangement remembered per slot
        _ = session.handleKey(.digit(3))
        XCTAssertEqual(session.palette[2].r, 0x33)
        _ = session.handleKey(.S)
        XCTAssertTrue(lines.take().contains("saved color set 3 Three"))
        XCTAssertEqual(store.loadColorSets()[3]!.colors, ["#000000", "#111111", "#333333", "#222222"])
        _ = session.handleKey(.c)  // index restarted from the saved base
        XCTAssertTrue(lines.take().contains("arrangement 2/24"))
        XCTAssertEqual(session.palette.map(\.r), [0x00, 0x11, 0x22, 0x33])
        _ = session.handleKey(.C)  // reverse: back to the saved arrangement
        XCTAssertTrue(lines.take().contains("arrangement 1/24"))
        _ = session.handleKey(.C)  // wraps backward to 24
        XCTAssertTrue(lines.take().contains("arrangement 24/24"))
        _ = session.handleKey(.space)
        _ = session.handleKey(.C)  // live while paused too
        XCTAssertTrue(lines.take().contains("arrangement 23/24"))
    }

    // MARK: PT-25 continuous scrolling (R-U3)

    func testScrollOffsetSemantics() throws {
        let session = makeSession(try makeStore())
        _ = session.handleKey(.a)  // keep auto-init from re-seeding during the test
        XCTAssertEqual(session.scrollOffset, 0)  // filling
        session.tick(session.delay * Double(session.rows))
        XCTAssertEqual(session.history.count, session.rows + 1)
        XCTAssertEqual(session.scrollOffset, 1)  // default speed: discrete
        _ = session.handleKey(.minus)
        _ = session.handleKey(.minus)  // 4x the delay: continuous
        XCTAssertGreaterThan(session.delay, Session.smoothScrollDelay)
        session.tick(session.delay * 0.25)
        XCTAssertEqual(session.scrollOffset, 0.25, accuracy: 1e-9)
        session.tick(session.delay * 0.5)
        XCTAssertEqual(session.scrollOffset, 0.75, accuracy: 1e-9)
        let g = session.automaton.generation
        session.tick(session.delay * 0.3)  // crosses a generation: wraps
        XCTAssertEqual(session.automaton.generation, g + 1)
        XCTAssertEqual(session.scrollOffset, 0.05, accuracy: 1e-9)
        _ = session.handleKey(.space)
        XCTAssertEqual(session.scrollOffset, 1)  // paused: newest row fully shown
        _ = session.handleKey(.space)
        session.tick(0.0)  // seamless resume
        XCTAssertEqual(session.automaton.generation, g + 2)
        XCTAssertEqual(session.scrollOffset, 0)
    }

    // MARK: PT-26 color set review mode (R-V)

    func grey(_ v: Int) -> [String] { (0..<4).map { String(format: "#%02X%02X%02X", v + $0, v + $0, v + $0) } }

    func reviewStore() throws -> Store {
        let store = try makeStore()
        // Slots in file order 0..9 (as Python writes them), a pool set, one drop.
        var sets: [ColorSetEntry] = []
        for slot in 0...9 { sets.append(ColorSetEntry(slot: slot, name: "S\(slot)", colors: grey(slot * 10))) }
        sets.append(ColorSetEntry(slot: nil, name: "PoolA", colors: grey(100)))
        store.saveColorSetFile(ColorSetFile(sets: sets, dropped: ["Rejected"]))
        let candidates = """
            {"palettes": [
              {"index": 0, "name": "S3", "colors": ["#000000", "#000000", "#000000", "#000000"]},
              {"index": 1, "name": "Rejected", "colors": ["#000000", "#000000", "#000000", "#000000"]},
              {"index": 2, "name": "CandB", "colors": ["#0B0B0B", "#0C0C0C", "#0D0D0D", "#0E0E0E"]},
              {"index": 3, "name": "CandC", "colors": ["#1B1B1B", "#1C1C1C", "#1D1D1D", "#1E1E1E"]}]}
            """
        try candidates.write(to: store.candidatePalettesFile, atomically: true, encoding: .utf8)
        return store
    }

    func testReviewOrderAndStepping() throws {
        let lines = Lines()
        let store = try reviewStore()
        let session = makeSession(store, lines: lines, review: true)
        let names = session.reviewEntries.map(\.name)
        XCTAssertEqual(names, ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S0", "PoolA", "CandB", "CandC"])
        XCTAssertEqual(session.droppedNames, ["Rejected"])
        XCTAssertTrue(lines.take().contains("review 1/13 S1"))
        XCTAssertEqual(session.palette[0], RGB(hex: "#0A0A0A"))  // S1 = grey(10)

        _ = session.handleKey(.N)
        XCTAssertEqual(lines.take(), "review 2/13 S2")
        XCTAssertEqual(session.palette[0], RGB(hex: "#141414"))
        _ = session.handleKey(.P)
        _ = session.handleKey(.P)  // past the start: wraps to the end
        let out = lines.take()
        XCTAssertTrue(out.contains("review wrapped") && out.contains("review 13/13 CandC"))
        _ = session.handleKey(.digit(5))  // digits are disabled in review mode
        XCTAssertEqual(session.palette[0], RGB(hex: "#1B1B1B"))
        _ = session.handleKey(.N)  // past the end: wraps to the start
        XCTAssertTrue(lines.take().contains("review wrapped"))
        XCTAssertEqual(session.reviewIndex, 0)
        _ = session.handleKey(.space)
        _ = session.handleKey(.N)  // live while paused
        XCTAssertEqual(session.reviewIndex, 1)
    }

    func testReviewDropSaveAndSlotRotation() throws {
        let lines = Lines()
        let store = try reviewStore()
        let session = makeSession(store, lines: lines, review: true)
        _ = session.handleKey(.c)  // arrange S1: preview only, never saved (R-V6)
        _ = session.handleKey(.N)
        _ = session.handleKey(.X)  // drop S2: advances to S3 and saves at once
        var out = lines.take()
        XCTAssertTrue(out.contains("dropped S2") && out.contains("review 2/12 S3"))
        XCTAssertTrue(out.contains("saved 12 color sets, 2 dropped"))
        XCTAssertEqual(store.loadColorSetFile().dropped, ["Rejected", "S2"])
        XCTAssertEqual(session.palette[0], RGB(hex: "#1E1E1E"))  // S3 = grey(30)
        for _ in 0..<10 { _ = session.handleKey(.N) }  // to CandC (last)
        _ = session.handleKey(.X)  // drop the last: wraps to the start
        out = lines.take()
        XCTAssertTrue(out.contains("dropped CandC") && out.contains("review wrapped") && out.contains("review 1/11 S1"))
        XCTAssertTrue(out.contains("saved 11 color sets, 3 dropped"))  // auto-saved on drop
        _ = session.handleKey(.S)  // no binding in review mode: nothing printed
        XCTAssertEqual(lines.take(), "")
        let file = store.loadColorSetFile()
        XCTAssertEqual(file.dropped, ["Rejected", "S2", "CandC"])
        let bySlot = Dictionary(uniqueKeysWithValues: file.sets.compactMap { e in e.slot.map { ($0, e.name) } })
        // Slots rotate down: S3 takes key 2 ... S0 takes key 9, PoolA fills key 0.
        XCTAssertEqual(bySlot, [1: "S1", 2: "S3", 3: "S4", 4: "S5", 5: "S6", 6: "S7", 7: "S8", 8: "S9", 9: "S0", 0: "PoolA"])
        XCTAssertEqual(file.sets.filter { $0.slot == nil }.map(\.name), ["CandB"])
        XCTAssertEqual(file.sets.first { $0.name == "S1" }!.colors, grey(10))  // arrangement not baked

        // A second review run reloads the same order and does not resurrect drops.
        let again = makeSession(store, review: true)
        XCTAssertEqual(again.reviewEntries.map(\.name), ["S1", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S0", "PoolA", "CandB"])
        XCTAssertEqual(again.droppedNames, ["Rejected", "S2", "CandC"])
        _ = again.handleKey(.X)  // drop S1; finish() saves at exit
        again.finish()
        XCTAssertEqual(store.loadColorSets()[1]!.name, "S3")
        XCTAssertEqual(store.loadColorSetFile().dropped.last, "S1")
    }

    func testReviewKeysAreInertOutsideReviewMode() throws {
        let store = try reviewStore()
        let session = makeSession(store)
        XCTAssertFalse(session.reviewMode)
        let palette = session.palette
        _ = session.handleKey(.N)
        _ = session.handleKey(.P)
        _ = session.handleKey(.X)
        XCTAssertEqual(session.palette, palette)
        XCTAssertEqual(store.loadColorSetFile().dropped, ["Rejected"])
        session.finish()  // no review: nothing written
        XCTAssertEqual(store.loadColorSetFile().sets.count, 11)
    }

    // MARK: PT-28 screensaver review mode (R-W)

    func testScreensaverReviewLifecycle() throws {
        let lines = Lines()
        let store = try reviewStore()
        let file = store.stateDir.deletingLastPathComponent().appendingPathComponent("saver.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let session = makeSession(store, lines: lines, screensaver: file)
        XCTAssertTrue(session.screensaverMode && !session.reviewMode)
        XCTAssertEqual(Store.loadScreensaver(file), [])  // a new, empty file was created
        XCTAssertNil(session.pairIndex)
        XCTAssertTrue(lines.take().contains("screensaver saver.json: 0 pairs"))
        let rule0 = session.automaton.rule

        _ = session.handleKey(.N)  // nothing to step through
        XCTAssertEqual(lines.take(), "")
        _ = session.handleKey(.s)
        XCTAssertTrue(lines.take().contains("no pair under review"))

        _ = session.handleKey(.digit(3))  // S3 = grey(30)
        _ = session.handleKey(.c)  // arranged (0,1,3,2)
        _ = session.handleKey(.S)  // append pair 1; position unchanged
        var out = lines.take()
        XCTAssertTrue(out.contains("added pair 1/1") && out.contains("saved 1 pair to saver.json"))
        XCTAssertNil(session.pairIndex)
        var saved = Store.loadScreensaver(file)!
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].rule, rule0.id)
        XCTAssertEqual(saved[0].colorset, "S3")
        XCTAssertEqual(saved[0].colors, ["#1E1E1E", "#1F1F1F", "#212121", "#202020"])

        _ = session.handleKey(.m)  // a different rule, then append pair 2 with pool set via ']'
        let rule1 = session.automaton.rule
        _ = session.handleKey(.poolNext)  // from S3 to S4
        XCTAssertTrue(lines.take().contains("color set S4"))
        _ = session.handleKey(.S)
        XCTAssertEqual(Store.loadScreensaver(file)!.count, 2)

        _ = session.handleKey(.N)  // activates pair 1: rule0, S3 arranged
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertEqual(session.automaton.rule, rule0)
        XCTAssertEqual(session.palette.map(\.r), [0x1E, 0x1F, 0x21, 0x20])
        XCTAssertTrue(lines.take().contains("screensaver 1/2 S3"))
        _ = session.handleKey(.P)  // no wrap at the start
        XCTAssertTrue(lines.take().contains("screensaver end"))
        XCTAssertEqual(session.pairIndex, 0)

        _ = session.handleKey(.digit(5))  // modify pair 1's color set and save in place
        _ = session.handleKey(.s)
        out = lines.take()
        XCTAssertTrue(out.contains("saved pair 1/2") && out.contains("saved 2 pairs to saver.json"))
        saved = Store.loadScreensaver(file)!
        XCTAssertEqual(saved[0].colorset, "S5")
        XCTAssertEqual(saved[0].colors, grey(50))
        XCTAssertEqual(saved[1].rule, rule1.id)

        _ = session.handleKey(.N)  // pair 2
        XCTAssertEqual(session.automaton.rule, rule1)
        _ = session.handleKey(.N)
        XCTAssertTrue(lines.take().contains("screensaver end"))
        _ = session.handleKey(.X)  // delete the last: shows the previous
        out = lines.take()
        XCTAssertTrue(out.contains("deleted pair 2/2") && out.contains("saved 1 pair to saver.json"))
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertEqual(Store.loadScreensaver(file)!.count, 1)
        _ = session.handleKey(.X)
        XCTAssertNil(session.pairIndex)
        XCTAssertEqual(Store.loadScreensaver(file), [])

        // Startup with a non-empty file activates pair 1.
        Store.saveScreensaver([ScreensaverPair(rule: rule1.id, colorset: "S7", colors: grey(70))], to: file)
        let again = makeSession(store, screensaver: file)
        XCTAssertEqual(again.pairIndex, 0)
        XCTAssertEqual(again.automaton.rule, rule1)
        XCTAssertEqual(again.palette[0], RGB(hex: "#464646"))
        _ = again.handleKey(.poolPrev)  // '[' walks the pool backward from S7
        XCTAssertEqual(again.palette[0], RGB(hex: "#3C3C3C"))  // S6
    }

    func testScreensaverKeysInertOutsideMode() throws {
        let session = makeSession(try reviewStore())
        XCTAssertFalse(session.screensaverMode)
        let palette = session.palette
        _ = session.handleKey(.poolNext)
        XCTAssertEqual(session.palette, palette)
        _ = session.handleKey(.N)
        _ = session.handleKey(.X)
        XCTAssertEqual(session.pairs, [])
    }

    // MARK: PT-30 consistency check: grouped view, file order preserved (R-W7)

    func testConsistencyCheckGroupsByRuleForViewOnly() throws {
        let lines = Lines()
        let store = try reviewStore()
        let file = store.stateDir.deletingLastPathComponent().appendingPathComponent("saver.json")
        let a = String(repeating: "0", count: 20), b = String(repeating: "1", count: 20), c = String(repeating: "2", count: 20)
        // File order: A, B, A, C, B  (color sets S1..S5 mark the positions)
        let original = [(a, "S1"), (b, "S2"), (a, "S3"), (c, "S4"), (b, "S5")].map { rule, set in
            ScreensaverPair(rule: rule, colorset: set, colors: grey(Int(set.dropFirst())! * 10))
        }
        Store.saveScreensaver(original, to: file)

        let session = makeSession(store, lines: lines, screensaver: file, grouped: true)
        XCTAssertEqual(session.viewOrder, [0, 2, 1, 4, 3])  // A A B B C
        var out = lines.take()
        XCTAssertTrue(out.contains("--- rule group 1/3 ---") && out.contains("screensaver 1/5 S1"))
        _ = session.handleKey(.N)
        out = lines.take()
        XCTAssertTrue(out.contains("screensaver 2/5 S3") && !out.contains("rule group"))
        _ = session.handleKey(.N)
        out = lines.take()
        XCTAssertTrue(out.contains("--- rule group 2/3 ---") && out.contains("screensaver 3/5 S2"))
        XCTAssertEqual(session.pairIndex, 1)  // file position of S2

        _ = session.handleKey(.S)  // append a B pair: end of file, but grouped with B in the view
        XCTAssertEqual(session.pairs.count, 6)
        XCTAssertEqual(session.viewOrder, [0, 2, 1, 4, 5, 3])
        XCTAssertEqual(session.viewPosition, 2)  // still on S2
        _ = session.handleKey(.N)  // S5
        _ = session.handleKey(.N)  // the appended pair, same group: no marker
        out = lines.take()
        XCTAssertTrue(out.contains("screensaver 5/6") && !out.contains("rule group"))
        XCTAssertEqual(session.pairIndex, 5)
        _ = session.handleKey(.N)  // C
        XCTAssertTrue(lines.take().contains("--- rule group 3/3 ---"))
        XCTAssertEqual(session.pairIndex, 3)

        _ = session.handleKey(.digit(7))  // modify C's color set in place
        _ = session.handleKey(.s)
        var saved = Store.loadScreensaver(file)!
        XCTAssertEqual(saved.map(\.colorset), ["S1", "S2", "S3", "S7", "S5", "S2"])  // file order kept
        XCTAssertEqual(saved[5].rule, b)

        _ = session.handleKey(.P)  // back to the appended pair (view 5/6)
        _ = session.handleKey(.X)  // delete it: file loses its last entry
        saved = Store.loadScreensaver(file)!
        XCTAssertEqual(saved.map(\.colorset), ["S1", "S2", "S3", "S7", "S5"])
        XCTAssertEqual(session.viewPosition, 4)  // the pair now at that view position: C
        XCTAssertEqual(session.pairIndex, 3)
    }
}
