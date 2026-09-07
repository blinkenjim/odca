import Foundation
import XCTest

@testable import ODCAKit

/// Layer 2 of TESTS.md: session properties PT-9, PT-10, PT-10a, PT-13..PT-24.
/// All file access goes to a temp Store; the search is never started.
final class SessionTests: XCTestCase {
    func makeStore(currentRule: Rule? = nil) throws -> Store {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odca-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store(
            stateDir: dir.appendingPathComponent("state"),
            libraryFile: dir.appendingPathComponent("library.json"),
            candidatePalettesFile: dir.appendingPathComponent("candidates.json"))
        if let rule = currentRule { store.saveRule(rule) }
        return store
    }

    /// An odca file beside the store's state, holding the rules with default colors.
    func odcaFile(_ store: Store, rules: [Rule] = [], name: String = "looks.odca") -> URL {
        let url = store.stateDir.deletingLastPathComponent().appendingPathComponent(name)
        if !rules.isEmpty {
            let d = Store.defaultColorSets[1]!
            Store.saveOdcaFile(rules.map { Look(rule: $0.id, colorset: d.name, colors: d.colors) }, to: url)
        }
        return url
    }

    /// A session whose terminal output is captured into `lines`.
    func makeSession(_ store: Store, seed: UInt64 = 1, lines: Lines? = nil,
                     review: Bool = false, select: URL? = nil, play: URL? = nil, shuffle: Bool = false,
                     initialDelay: Double = Session.initialDelay,
                     playTimeout: Double = Session.playTimeout, playGrace: Double = Session.playGrace) -> Session {
        let sink: (String) -> Void = lines.map { l in { l.all.append($0) } } ?? { print($0) }
        return Session(cols: 32, rows: 16, store: store,
                       search: CandidateSearch(workers: 0), rng: Xoshiro256(seed: seed),
                       reviewMode: review, selectFile: select, playFile: play, shuffle: shuffle,
                       initialDelay: initialDelay, playTimeout: playTimeout, playGrace: playGrace, output: sink)
    }

    func testWatchdogAndGraceAreConstructionParameters() throws {  // PT-31, R-X2, R-X3
        let lines = Lines()
        let store = try reviewStore()
        let file = odcaFile(store, name: "saver.odca")
        Store.saveOdcaFile([Look(rule: allProducible.id, colorset: "A", colors: grey(10)),
                            Look(rule: allProducible.id, colorset: "B", colors: grey(20))], to: file)
        let session = makeSession(store, lines: lines, play: file, playTimeout: 20, playGrace: 10)
        _ = session.handleKey(.a)  // only the clocks transition
        session.tick(19)
        XCTAssertEqual(session.lookIndex, 0)
        session.tick(1.5)  // 20.5 s: the watchdog has expired and the grace period is long satisfied
        XCTAssertEqual(session.lookIndex, 1)
        XCTAssertTrue(lines.take().contains("look 2/2 B (timeout)"))
        session.tick(15)
        _ = session.handleKey(.i)  // 15 s in: the grace period restarts, the watchdog does not
        session.tick(6)  // 21 s: expired, but only 6 s since the re-seed
        XCTAssertEqual(session.lookIndex, 1)
        session.tick(4.5)  // 25.5 s: 10.5 s since the re-seed
        XCTAssertEqual(session.lookIndex, 0)
    }

    func testInitialDelayScalesTheSpeedAndTheThreshold() throws {  // PT-25, R-U5, R-U3
        let session = makeSession(try makeStore(), initialDelay: Session.initialDelay / 4)  // --1
        _ = session.handleKey(.a)
        XCTAssertEqual(session.delay, Session.initialDelay / 4)
        session.tick(session.delay * 16)  // a screenful in a quarter of the default time
        XCTAssertEqual(session.history.count, 17)
        XCTAssertEqual(session.scrollOffset, 1)  // fast: discrete
        _ = session.handleKey(.minus)  // twice the initial delay: still discrete
        XCTAssertEqual(session.delay, Session.initialDelay / 2)
        XCTAssertEqual(session.scrollOffset, 1)
        _ = session.handleKey(.minus)  // four times: continuous, though discrete at the default size
        XCTAssertEqual(session.delay, Session.initialDelay)
        session.tick(session.delay / 4)
        XCTAssertEqual(session.scrollOffset, 0.25, accuracy: 1e-9)
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

    func testCycleWithUnsavedSlot() throws {  // PT-10
        let saved = fourSaved
        let outside = try Rule(id: "01230123012301230123")
        let store = try makeStore(currentRule: outside)
        let session = makeSession(store, select: odcaFile(store, rules: saved))
        // A non-empty file opens on look 1 with the unsaved slot empty (R-W1) ...
        XCTAssertEqual(session.lookIndex, 0)
        XCTAssertNil(session.unsavedRule)
        XCTAssertEqual(session.automaton.rule, saved[0])
        _ = session.handleKey(.r)  // ... until r fills it (m on a look is an edit of it, 3.16.0)
        let first = session.automaton.rule
        XCTAssertNil(session.lookIndex)
        XCTAssertEqual(session.unsavedRule, first)
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, first)
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, saved[3])
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, first)
        _ = session.handleKey(.m)  // on the slot, a mutation replaces the unsaved rule and stays there
        let mutant = session.automaton.rule
        XCTAssertNil(session.lookIndex)
        XCTAssertEqual(session.unsavedRule, mutant)
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, mutant)
    }

    func testCycleStartupOnFirstLook() throws {  // PT-10a
        let saved = fourSaved
        let store = try makeStore(currentRule: saved[2])
        let session = makeSession(store, select: odcaFile(store, rules: saved))
        XCTAssertEqual(session.lookIndex, 0)
        XCTAssertNil(session.unsavedRule)
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[1])
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertTrue(session.handleKey(.p))  // wraps with no unsaved stop
        XCTAssertEqual(session.automaton.rule, saved[3])
        _ = session.handleKey(.r)  // a fresh rule: the unsaved slot reappears holding it
        let fresh = session.automaton.rule
        XCTAssertEqual(session.unsavedRule, fresh)
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, fresh)
    }

    func testCycleEmptyFileAndNoFile() throws {  // R-B4
        let lines = Lines()
        let outside = try Rule(id: "01230123012301230123")
        let store = try makeStore(currentRule: outside)
        let session = makeSession(store, lines: lines, select: odcaFile(store))
        XCTAssertEqual(session.unsavedRule, outside)
        XCTAssertEqual(session.looks, [])
        _ = lines.take()
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, outside)
        XCTAssertTrue(lines.take().contains("no looks"))
        let base = makeSession(try makeStore())  // no program: n/p have nothing to cycle
        let rule = base.automaton.rule
        XCTAssertTrue(base.handleKey(.n))
        XCTAssertEqual(base.automaton.rule, rule)
        XCTAssertNil(base.lookIndex)
    }

    // MARK: PT-13, PT-14

    func testPauseModality() throws {
        let store = try makeStore()
        let session = makeSession(store)
        XCTAssertTrue(session.handleKey(.space))
        XCTAssertTrue(session.paused)
        let rule = session.automaton.rule
        let cells = session.automaton.cells
        let delay = session.delay
        let index = session.lookIndex
        for key: Session.Key in [.r, .m, .u, .i, .n, .p, .a, .plus, .minus] {
            XCTAssertTrue(session.handleKey(key))
        }
        XCTAssertEqual(session.automaton.rule, rule)
        XCTAssertEqual(session.automaton.cells, cells)
        XCTAssertEqual(session.delay, delay)
        XCTAssertEqual(session.lookIndex, index)
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
        // (unpaused 's' is the save key of odca-select; without a program it saves nothing)
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
        XCTAssertTrue(lines.take().contains("color set Three arrangement 2/24"))
        for _ in 0..<23 { _ = session.handleKey(.c) }
        XCTAssertEqual(session.palette.map(\.r), [0x00, 0x11, 0x22, 0x33])  // wrapped
        _ = session.handleKey(.c)
        _ = session.handleKey(.digit(1))  // arrangement remembered per slot
        _ = session.handleKey(.digit(3))
        XCTAssertEqual(session.palette[2].r, 0x33)
        _ = session.handleKey(.S)
        XCTAssertTrue(lines.take().contains("saved color set Three"))
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

        let g0 = session.automaton.generation
        _ = session.handleKey(.N)
        XCTAssertEqual(lines.take(), "review 2/13 S2")
        XCTAssertEqual(session.palette[0], RGB(hex: "#141414"))
        XCTAssertEqual(session.automaton.generation, g0 + session.rows)  // R-V7: a screenful at once
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
        _ = session.handleKey(.poolNext)  // '[' / ']' are synonyms for P / N here (R-K17)
        XCTAssertEqual(session.reviewIndex, 2)
        _ = session.handleKey(.poolPrev)
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

    // MARK: PT-28 odca-select (R-W)

    func testSelectLifecycle() throws {
        let lines = Lines()
        let store = try reviewStore()
        let file = odcaFile(store, name: "saver.odca")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let session = makeSession(store, lines: lines, select: file)
        XCTAssertTrue(session.selectMode && !session.reviewMode && !session.playMode)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))  // created by the first save or at exit
        XCTAssertNil(session.lookIndex)
        XCTAssertEqual(session.unsavedRule, session.automaton.rule)
        XCTAssertTrue(lines.take().contains("odca saver.odca: 0 looks"))
        let rule0 = session.automaton.rule
        _ = session.handleKey(.n)
        XCTAssertTrue(lines.take().contains("no looks"))

        _ = session.handleKey(.digit(3))  // S3 = grey(30)
        _ = session.handleKey(.c)  // arranged (0,1,3,2)
        _ = session.handleKey(.s)  // on the unsaved slot: s appends, as S would (R-W4)
        var out = lines.take()
        XCTAssertTrue(out.contains("added look 1/1") && out.contains("saved 1 look to saver.odca"))
        XCTAssertNil(session.lookIndex)  // the position is unchanged
        XCTAssertEqual(Store.loadOdcaFile(file),
                       [Look(rule: rule0.id, colorset: "S3", colors: ["#1E1E1E", "#1F1F1F", "#212121", "#202020"])])

        _ = session.handleKey(.m)
        let rule1 = session.automaton.rule
        _ = session.handleKey(.poolNext)  // from S3 to S4
        XCTAssertTrue(lines.take().contains("color set S4"))
        _ = session.handleKey(.S)  // append a copy of the screen
        XCTAssertEqual(Store.loadOdcaFile(file)!.count, 2)
        XCTAssertNil(session.lookIndex)

        let gBefore = session.automaton.generation
        _ = session.handleKey(.n)  // look 1: rule0, S3 arranged, and a screenful at once
        XCTAssertEqual(session.lookIndex, 0)
        XCTAssertEqual(session.automaton.rule, rule0)
        XCTAssertEqual(session.automaton.generation, gBefore + session.rows)  // R-W8
        XCTAssertEqual(session.palette.map(\.r), [0x1E, 0x1F, 0x21, 0x20])
        XCTAssertTrue(lines.take().contains("look 1/2 S3"))

        _ = session.handleKey(.digit(5))
        _ = session.handleKey(.s)  // on a look: rewrite its color set in place, rule kept
        out = lines.take()
        XCTAssertTrue(out.contains("saved look 1/2") && out.contains("saved 2 looks to saver.odca"))
        var saved = Store.loadOdcaFile(file)!
        XCTAssertEqual(saved[0].rule, rule0.id)
        XCTAssertEqual(saved[0].colorset, "S5")
        XCTAssertEqual(saved[0].colors, grey(50))
        XCTAssertEqual(saved[1].rule, rule1.id)

        _ = session.handleKey(.n)  // look 2
        XCTAssertEqual(session.automaton.rule, rule1)
        XCTAssertEqual(session.lookIndex, 1)
        _ = session.handleKey(.n)  // the unsaved slot: the mutant with the set it arrived with
        XCTAssertTrue(lines.take().contains("unsaved rule"))
        XCTAssertNil(session.lookIndex)
        XCTAssertEqual(session.automaton.rule, rule1)
        _ = session.handleKey(.X)  // nothing under review: no-op
        XCTAssertEqual(Store.loadOdcaFile(file)!.count, 2)
        _ = session.handleKey(.p)  // back to look 2
        _ = session.handleKey(.X)  // delete the last: shows the previous
        out = lines.take()
        XCTAssertTrue(out.contains("deleted look 2/2") && out.contains("saved 1 look to saver.odca"))
        XCTAssertEqual(session.lookIndex, 0)
        XCTAssertEqual(Store.loadOdcaFile(file)!.count, 1)
        _ = session.handleKey(.X)
        XCTAssertNil(session.lookIndex)
        XCTAssertEqual(Store.loadOdcaFile(file), [])
        XCTAssertEqual(session.unsavedRule, session.automaton.rule)  // keeps running as the unsaved rule

        session.finish()  // exit writes the file
        XCTAssertEqual(Store.loadOdcaFile(file), [])
        Store.saveOdcaFile([Look(rule: rule1.id, colorset: "S7", colors: grey(70))], to: file)
        let again = makeSession(store, select: file)
        XCTAssertEqual(again.lookIndex, 0)
        XCTAssertEqual(again.automaton.rule, rule1)
        XCTAssertEqual(again.palette[0], RGB(hex: "#464646"))
        _ = again.handleKey(.poolPrev)  // '[' walks the pool backward from S7
        XCTAssertEqual(again.palette[0], RGB(hex: "#3C3C3C"))  // S6
        again.finish()
        XCTAssertEqual(Store.loadOdcaFile(file)!.first!.colorset, "S7")  // exit rewrites what it loaded
        saved = Store.loadOdcaFile(file)!
        XCTAssertEqual(saved.count, 1)
    }

    func testSelectKeysInertElsewhere() throws {
        let session = makeSession(try reviewStore())
        XCTAssertFalse(session.selectMode)
        for key: Session.Key in [.N, .P, .X, .R, .s, .S] { _ = session.handleKey(key) }
        XCTAssertEqual(session.looks, [])
        XCTAssertFalse(session.grouped)
    }

    // MARK: PT-30 R toggles the grouped order; file order preserved (R-W7, R-U10)

    func testGroupedOrderToggle() throws {
        let lines = Lines()
        let store = try reviewStore()
        let file = odcaFile(store, name: "saver.odca")
        let a = String(repeating: "0", count: 20), b = String(repeating: "1", count: 20), c = String(repeating: "2", count: 20)
        // File order: A, B, A, C, B  (color sets S1..S5 mark the positions)
        let original = [(a, "S1"), (b, "S2"), (a, "S3"), (c, "S4"), (b, "S5")].map { rule, set in
            Look(rule: rule, colorset: set, colors: grey(Int(set.dropFirst())! * 10))
        }
        Store.saveOdcaFile(original, to: file)

        let session = makeSession(store, lines: lines, select: file)
        XCTAssertEqual(session.viewOrder, [0, 1, 2, 3, 4])
        XCTAssertFalse(session.grouped)
        _ = lines.take()
        _ = session.handleKey(.R)  // grouped by rule: A A B B C
        var out = lines.take()
        XCTAssertTrue(out.contains("look order grouped by rule"))
        XCTAssertTrue(session.grouped)
        XCTAssertEqual(session.viewOrder, [0, 2, 1, 4, 3])
        XCTAssertEqual(session.lookIndex, 0)
        XCTAssertEqual(session.viewPosition, 0)  // the look under review is kept
        XCTAssertTrue(session.inverted)  // R-U10
        XCTAssertEqual(session.flashRemaining, Session.flashSeconds)
        session.tick(0.1)
        XCTAssertTrue(session.inverted)
        _ = session.handleKey(.space)
        session.tick(0.2)  // the flash ends on the wall clock even while paused
        XCTAssertFalse(session.inverted)
        _ = session.handleKey(.space)
        _ = session.handleKey(.n)
        out = lines.take()
        XCTAssertTrue(out.contains("look 2/5 S3") && !out.contains("rule group"))
        _ = session.handleKey(.n)
        out = lines.take()
        XCTAssertTrue(out.contains("--- rule group 2/3 ---") && out.contains("look 3/5 S2"))
        XCTAssertEqual(session.lookIndex, 1)  // file position of S2

        _ = session.handleKey(.S)  // append a B look: end of file, but grouped with B in the view
        XCTAssertEqual(session.looks.count, 6)
        XCTAssertEqual(session.viewOrder, [0, 2, 1, 4, 5, 3])
        XCTAssertEqual(session.viewPosition, 2)  // still on S2
        _ = session.handleKey(.n)  // S5
        _ = session.handleKey(.n)  // the appended look, same group: no marker
        out = lines.take()
        XCTAssertTrue(out.contains("look 5/6") && !out.contains("rule group"))
        XCTAssertEqual(session.lookIndex, 5)
        _ = session.handleKey(.n)  // C
        XCTAssertTrue(lines.take().contains("--- rule group 3/3 ---"))
        XCTAssertEqual(session.lookIndex, 3)

        _ = session.handleKey(.digit(7))  // modify C's color set in place
        _ = session.handleKey(.s)
        var saved = Store.loadOdcaFile(file)!
        XCTAssertEqual(saved.map(\.colorset), ["S1", "S2", "S3", "S7", "S5", "S2"])  // file order kept
        XCTAssertEqual(saved[5].rule, b)

        _ = session.handleKey(.p)  // back to the appended look (view 5/6)
        _ = session.handleKey(.X)  // delete it: file loses its last entry
        saved = Store.loadOdcaFile(file)!
        XCTAssertEqual(saved.map(\.colorset), ["S1", "S2", "S3", "S7", "S5"])
        XCTAssertEqual(session.viewPosition, 4)  // the look now at that view position: C
        XCTAssertEqual(session.lookIndex, 3)
        _ = session.handleKey(.R)  // back to file order, still on S7
        XCTAssertTrue(lines.take().contains("look order file order"))
        XCTAssertEqual(session.viewOrder, [0, 1, 2, 3, 4])
        XCTAssertEqual(session.viewPosition, 3)
    }

    // MARK: PT-31 odca (R-X)

    func testPlaysLooksInOrderAndLoops() throws {
        let lines = Lines()
        let store = try reviewStore()
        let file = odcaFile(store, name: "saver.odca")
        let dies = allZero  // repeating (period 1) within a screenful
        Store.saveOdcaFile([Look(rule: dies.id, colorset: "A", colors: grey(10)),
                            Look(rule: dies.id, colorset: "B", colors: grey(20))], to: file)
        let session = makeSession(store, lines: lines, play: file)
        XCTAssertTrue(session.playMode && !session.selectMode && !session.reviewMode)
        XCTAssertEqual(session.lookIndex, 0)
        XCTAssertEqual(session.automaton.rule, dies)
        XCTAssertEqual(session.palette[0], RGB(hex: "#0A0A0A"))
        XCTAssertEqual(session.automaton.generation, 0)  // freshly seeded
        var out = lines.take()
        XCTAssertTrue(out.contains("odca saver.odca: 2 looks") && out.contains("look 1/2 A"))
        XCTAssertFalse(out.contains("("))  // no reason on the first look

        // Before the watchdog expires, boredom re-seeds in place: the look keeps its screen time.
        for _ in 0..<17 { session.tick(1.0 / 60.0) }
        XCTAssertEqual(session.lookIndex, 0)
        XCTAssertEqual(session.automaton.generation, 0)  // re-seeded
        out = lines.take()
        XCTAssertTrue(out.contains("auto-init (repeating (period 1))") && !out.contains("look 2/2"))

        // Run out the watchdog without firings (auto-init off), re-seed by hand just before
        // expiry so the grace period is unsatisfied at expiry, then re-arm: the next firing
        // transitions instead of re-seeding in place, carrying its reason.
        _ = session.handleKey(.a)
        session.tick(110)
        XCTAssertEqual(session.lookIndex, 0)
        _ = session.handleKey(.i)  // grace restarts; the watchdog does not
        XCTAssertEqual(session.playElapsed, 110, accuracy: 1)
        _ = session.handleKey(.a)
        _ = lines.take()
        session.tick(10)  // the watchdog expires during this tick; boredom fires within it
        XCTAssertEqual(session.lookIndex, 1)
        XCTAssertLessThan(session.playElapsed, 1)  // the new look's clock started inside the tick
        XCTAssertEqual(session.palette[0], RGB(hex: "#141414"))
        // R-X5: rows from look A keep A's colors below the boundary; B's rows above it.
        let firstB = session.rowPalettes.firstIndex(of: 1)!
        XCTAssertEqual(session.rowPalettes[firstB - 1], 0)
        XCTAssertEqual(session.rowPalettes.last, 1)
        XCTAssertEqual(session.color(row: firstB - 1, col: 0), RGB(hex: "#0A0A0A"))  // state 0 under A
        XCTAssertEqual(session.paletteTable[0], RGB(hex: "#0A0A0A"))
        XCTAssertEqual(session.paletteTable[4], RGB(hex: "#141414"))
        out = lines.take()
        XCTAssertTrue(out.contains("look 2/2 B (repeating (period 1))"))

        // Looping: one long tick expires the watchdog and the firings inside it wrap to look 1.
        session.tick(Session.playTimeout)
        XCTAssertEqual(session.lookIndex, 0)
        out = lines.take()
        XCTAssertTrue(out.contains("look 1/2 A (repeating (period 1))"))
        XCTAssertFalse(out.contains("look 2/2"))

        // R-X6: N/P (and n/p) move through the looks by hand, wrapping, with a fresh seed each time.
        session.tick(1.0 / 60.0)
        _ = session.handleKey(.N)
        XCTAssertEqual(session.lookIndex, 1)
        XCTAssertEqual(session.automaton.generation, 0)
        XCTAssertTrue(lines.take().contains("look 2/2 B (next)"))
        _ = session.handleKey(.n)  // wraps
        XCTAssertEqual(session.lookIndex, 0)
        _ = session.handleKey(.space)
        _ = session.handleKey(.P)  // live while paused; wraps backward
        XCTAssertEqual(session.lookIndex, 1)
        XCTAssertTrue(lines.take().contains("look 2/2 B (previous)"))
        _ = session.handleKey(.space)
        for key: Session.Key in [.s, .S, .X] { _ = session.handleKey(key) }  // odca never writes the file
        XCTAssertEqual(Store.loadOdcaFile(file)!.count, 2)
    }

    func testPlayWatchdogAndGracePeriod() throws {
        let lines = Lines()
        let store = try reviewStore()
        let file = odcaFile(store, name: "saver.odca")
        Store.saveOdcaFile([Look(rule: allProducible.id, colorset: "A", colors: grey(10)),
                            Look(rule: allProducible.id, colorset: "B", colors: grey(20))], to: file)
        let session = makeSession(store, lines: lines, play: file)
        _ = session.handleKey(.a)  // auto-init off: only time sequences now
        for _ in 0..<50 { _ = session.handleKey(.plus) }  // fastest, so stepping is cheap
        _ = lines.take()
        session.tick(100)
        _ = session.handleKey(.space)
        session.tick(1000)  // paused time counts for nothing
        _ = session.handleKey(.space)
        _ = session.handleKey(.i)  // at 100 s: restarts the grace period, not the watchdog
        XCTAssertEqual(session.sinceInit, 0, accuracy: 1e-9)
        XCTAssertEqual(session.playElapsed, 100, accuracy: 1e-6)
        session.tick(20)  // 120 s: watchdog expired, but only 20 s since the re-seed
        XCTAssertEqual(session.lookIndex, 0)
        session.tick(39.5)
        XCTAssertEqual(session.lookIndex, 0)
        session.tick(1.0)  // 60 s since the re-seed: transition
        XCTAssertEqual(session.lookIndex, 1)
        XCTAssertTrue(lines.take().contains("look 2/2 B (timeout)"))
        XCTAssertEqual(session.playElapsed, 0, accuracy: 1e-9)

        // A quiet look transitions as soon as the watchdog expires (grace long satisfied).
        session.tick(119.5)
        XCTAssertEqual(session.lookIndex, 1)
        session.tick(1.0)
        XCTAssertEqual(session.lookIndex, 0)
    }

    func testShuffleIsAFreshPassWithoutRepeats() throws {  // PT-36
        let store = try reviewStore()
        let file = odcaFile(store, name: "saver.odca")
        let a = allProducible, b = try Rule(id: String(repeating: "1", count: 20)), c = try Rule(id: String(repeating: "2", count: 20))
        let x = grey(10), y = grey(20), z = grey(30)
        let looks = [Look(rule: a.id, colorset: "X", colors: x), Look(rule: a.id, colorset: "Y", colors: y),
                     Look(rule: b.id, colorset: "X'", colors: x.reversed()), Look(rule: b.id, colorset: "Z", colors: z),
                     Look(rule: c.id, colorset: "Y", colors: y), Look(rule: c.id, colorset: "Z", colors: z)]
        Store.saveOdcaFile(looks, to: file)
        let session = makeSession(store, play: file, shuffle: true)
        XCTAssertTrue(session.shuffle)
        var played = [session.lookIndex!]
        for _ in 0..<59 { _ = session.handleKey(.N); played.append(session.lookIndex!) }  // ten passes
        for p in 0..<10 {
            XCTAssertEqual(Array(played[(6 * p)..<(6 * p + 6)]).sorted(), Array(0..<6))  // every pass: every look once
        }
        for (i, j) in zip(played, played.dropFirst()) {  // never the same rule or color set in a row, seams included
            XCTAssertNotEqual(looks[i].rule, looks[j].rule, "\(i) then \(j)")
            XCTAssertNotEqual(looks[i].colors.sorted(), looks[j].colors.sorted(), "\(i) then \(j)")
        }
        _ = session.handleKey(.P)  // back one within the pass
        XCTAssertEqual(session.lookIndex, played[played.count - 2])
        let plain = makeSession(store, play: file)
        XCTAssertEqual(plain.playOrder, Array(0..<6))
        XCTAssertFalse(plain.shuffle)
        // No order can avoid a repeat: the requirement is dropped and the show goes on.
        Store.saveOdcaFile([Look(rule: a.id, colorset: "X", colors: x), Look(rule: a.id, colorset: "Y", colors: y)], to: file)
        let small = makeSession(store, play: file, shuffle: true)
        var pair = [small.lookIndex!]
        for _ in 0..<5 { _ = small.handleKey(.N); pair.append(small.lookIndex!) }
        for i in stride(from: 0, to: 6, by: 2) { XCTAssertEqual(Array(pair[i..<(i + 2)]).sorted(), [0, 1]) }
    }

    func testRowsKeepTheirColorsThroughQuickTransitions() throws {  // PT-31, R-X5
        let store = try reviewStore()
        let file = odcaFile(store, name: "saver.odca")
        Store.saveOdcaFile([Look(rule: allZero.id, colorset: "A", colors: grey(10)),
                            Look(rule: allZero.id, colorset: "B", colors: grey(20)),
                            Look(rule: allZero.id, colorset: "C", colors: grey(30))], to: file)
        let session = makeSession(store, play: file)
        _ = session.handleKey(.a)
        func painted(_ range: Range<Int>, _ colors: [String], line: UInt = #line) {
            for row in range {
                XCTAssertEqual(session.color(row: row, col: 0),
                               RGB(hex: colors[Int(session.history[row][0])]), "row \(row)", line: line)
            }
        }
        for _ in 0..<3 { session.tick(session.delay) }
        let rowsA = session.history.count
        _ = session.handleKey(.N)  // look 2, well within the screenful
        for _ in 0..<3 { session.tick(session.delay) }
        let rowsAB = session.history.count
        _ = session.handleKey(.N)  // look 3: a third color set on one screen
        for _ in 0..<3 { session.tick(session.delay) }
        painted(0..<rowsA, grey(10))
        painted(rowsA..<rowsAB, grey(20))
        painted(rowsAB..<session.history.count, grey(30))
        XCTAssertEqual(session.paletteTable.count, 12)  // three palettes
        _ = session.handleKey(.N)  // back to look 1: its palette is shared, not duplicated
        session.tick(session.delay)
        XCTAssertEqual(session.paletteTable.count, 12)
        // Many distinct palettes (arrangements of each set) pass the table's limit:
        // it is pruned to what remembered rows still use, and no row changes color.
        for i in 0..<(Session.paletteLimit + 10) {
            _ = session.handleKey(.N)  // the look shows its baked colors, arrangement 1
            for _ in 0..<(i % 23 + 1) { _ = session.handleKey(.c) }  // then a different arrangement each time round
            session.tick(session.delay)
        }
        painted(0..<rowsA, grey(10))
        painted(rowsA..<rowsAB, grey(20))
        XCTAssertGreaterThan(session.paletteTable.count, 4 * Session.paletteLimit)
        XCTAssertLessThanOrEqual(session.paletteTable.count, 4 * session.history.count)
    }

    func testMutatingALookEditsItInPlace() throws {  // PT-34, R-K3, R-W4
        let lines = Lines()
        let store = try reviewStore()
        let one = allZero, two = try Rule(id: String(repeating: "1", count: 20))
        let file = odcaFile(store, rules: [one, two], name: "saver.odca")
        let session = makeSession(store, lines: lines, select: file)
        XCTAssertEqual(session.lookIndex, 0)
        XCTAssertNil(session.unsavedRule)
        _ = session.handleKey(.m)  // an edit of look 1: the position stays, the unsaved slot stays empty
        XCTAssertNotEqual(session.automaton.rule, one)
        XCTAssertEqual(session.lookIndex, 0)
        XCTAssertEqual(session.viewPosition, 0)
        XCTAssertNil(session.unsavedRule)
        _ = session.handleKey(.u)  // walked back, still on look 1
        XCTAssertEqual(session.automaton.rule, one)
        XCTAssertEqual(session.lookIndex, 0)
        _ = session.handleKey(.m)
        let mutant = session.automaton.rule
        _ = session.handleKey(.digit(3))
        _ = lines.take()
        _ = session.handleKey(.s)  // rewrites look 1 in place: rule and colors
        XCTAssertTrue(lines.take().contains("saved look 1/2"))
        let looks = Store.loadOdcaFile(file)!
        XCTAssertEqual(looks.count, 2)
        XCTAssertEqual(looks[0].rule, mutant.id)
        XCTAssertEqual(looks[0].colorset, "S3")
        _ = session.handleKey(.m)  // a further edit, discarded by leaving the look
        _ = session.handleKey(.n)
        _ = session.handleKey(.p)
        XCTAssertEqual(session.automaton.rule, mutant)
        XCTAssertEqual(session.lookIndex, 0)
        _ = session.handleKey(.r)  // a fresh rule is a new exploration: the unsaved slot, as before
        XCTAssertNil(session.lookIndex)
        XCTAssertEqual(session.unsavedRule, session.automaton.rule)
        _ = session.handleKey(.m)  // on the unsaved slot the mutant stays there
        XCTAssertNil(session.lookIndex)
        XCTAssertEqual(session.unsavedRule, session.automaton.rule)
    }

    func testUUndoesEveryChangeSinceThePositionMoved() throws {  // PT-9, R-K19
        let store = try reviewStore()
        let one = allZero, two = try Rule(id: String(repeating: "1", count: 20))
        let session = makeSession(store, select: odcaFile(store, rules: [one, two], name: "saver.odca"))
        let depth = session.undoStack.count
        for _ in 0..<3 { _ = session.handleKey(.m) }
        XCTAssertNotEqual(session.automaton.rule, one)
        XCTAssertEqual(session.undoStack.count, depth + 3)
        _ = session.handleKey(.U)  // all three at once, still on look 1
        XCTAssertEqual(session.automaton.rule, one)
        XCTAssertEqual(session.lookIndex, 0)
        XCTAssertEqual(session.undoStack.count, depth)
        _ = session.handleKey(.U)  // nothing left since arriving here: a no-op
        XCTAssertEqual(session.automaton.rule, one)
        XCTAssertEqual(session.undoStack.count, depth)
        _ = session.handleKey(.n)  // look 2 (one push); edits here unwind to look 2, not further
        _ = session.handleKey(.m)
        _ = session.handleKey(.m)
        _ = session.handleKey(.U)
        XCTAssertEqual(session.automaton.rule, two)
        XCTAssertEqual(session.lookIndex, 1)
        XCTAssertEqual(session.undoStack.count, depth + 1)
        _ = session.handleKey(.r)  // the unsaved slot: U unwinds to the rule r brought
        let fresh = session.automaton.rule
        _ = session.handleKey(.m)
        _ = session.handleKey(.m)
        XCTAssertNotEqual(session.automaton.rule, fresh)
        _ = session.handleKey(.U)
        XCTAssertEqual(session.automaton.rule, fresh)
        XCTAssertNil(session.lookIndex)
        XCTAssertEqual(session.unsavedRule, fresh)
        _ = session.handleKey(.space)  // paused: U is not live, like u
        _ = session.handleKey(.m)
        XCTAssertEqual(session.automaton.rule, fresh)
    }

    // MARK: PT-32 resizing (R-U8)

    func testResizePreservesCenterAndUncoversHistory() throws {
        let lines = Lines()
        let session = makeSession(try makeStore(), lines: lines)
        _ = session.handleKey(.a)  // keep auto-init out of the way
        session.tick(session.delay * 40)  // 41 rows remembered, 16 + 1 shown
        XCTAssertEqual(session.history.count, 41)
        XCTAssertEqual(session.visibleStart, 41 - 17)
        let before = session.automaton.cells  // 32 cells
        let oldTop = session.history[0]

        // Narrower: the middle 20 cells survive, in every remembered row.
        XCTAssertTrue(session.resize(cols: 20, rows: 16))
        XCTAssertEqual(session.cols, 20)
        XCTAssertEqual(session.automaton.cells, Array(before[6..<26]))
        XCTAssertEqual(session.history[0], Array(oldTop[6..<26]))
        XCTAssertEqual(session.history.count, 41)  // history kept
        XCTAssertEqual(session.boringStreak, 0)  // detectors reset
        XCTAssertTrue(lines.take().contains("resized 20x16"))

        // Wider: the 20 stay centered, older rows padded with 0, the live row with random cells.
        let mid = session.automaton.cells
        XCTAssertTrue(session.resize(cols: 30, rows: 16))
        XCTAssertEqual(Array(session.automaton.cells[5..<25]), mid)
        XCTAssertEqual(Array(session.history[0][0..<5]), [0, 0, 0, 0, 0])
        XCTAssertEqual(session.history.last!, session.automaton.cells)
        for _ in 0..<5 { session.tick(session.delay) }
        XCTAssertEqual(session.automaton.cells.count, 30)

        // Taller: the window uncovers remembered rows instead of showing blank.
        XCTAssertTrue(session.resize(cols: 30, rows: 40))
        XCTAssertEqual(session.visibleStart, max(0, session.history.count - 41))
        XCTAssertEqual(session.scrollOffset, 1)  // 46 rows remembered > 40: still "full"
        XCTAssertFalse(session.resize(cols: 30, rows: 40))  // no change: nothing happens
        XCTAssertTrue(session.resize(cols: 1, rows: 0))  // clamped to the minimum
        XCTAssertEqual(session.cols, Session.minCols)
        XCTAssertEqual(session.rows, 1)
    }

    func testHistoryDepthIsBounded() throws {
        let session = makeSession(try makeStore())
        _ = session.handleKey(.a)
        for _ in 0..<50 { _ = session.handleKey(.plus) }
        for _ in 0..<3 { session.tick(1.0) }  // well past the depth (2000 steps per tick cap)
        XCTAssertEqual(session.history.count, Session.historyDepth)
        XCTAssertEqual(session.rowPalettes.count, Session.historyDepth)
    }

    // MARK: PT-33 the whole pool from every mode (R-K17)

    func testBracketsWalkThePoolInBaseMode() throws {
        let lines = Lines()
        let store = try reviewStore()  // slots 0-9 as S0..S9 plus pool-only PoolA
        let session = makeSession(store, lines: lines)
        XCTAssertEqual(session.activeSet?.name, "S1")
        XCTAssertEqual(session.palette[0], RGB(hex: "#0A0A0A"))
        _ = session.handleKey(.poolNext)
        XCTAssertEqual(session.activeSet?.name, "S2")
        XCTAssertEqual(session.colorSet, 2)  // a slotted set also becomes the digit position
        XCTAssertTrue(lines.take().contains("color set S2"))
        for _ in 0..<8 { _ = session.handleKey(.poolNext) }  // S3 ... S9, S0
        XCTAssertEqual(session.activeSet?.name, "S0")
        _ = session.handleKey(.poolNext)  // beyond the hot ten: the pool
        XCTAssertEqual(session.activeSet?.name, "PoolA")
        XCTAssertNil(session.activeSet?.slot)
        XCTAssertEqual(session.palette[0], RGB(hex: "#646464"))  // grey(100)
        _ = session.handleKey(.poolNext)  // wraps
        XCTAssertEqual(session.activeSet?.name, "S1")
        _ = session.handleKey(.poolPrev)
        _ = session.handleKey(.poolPrev)
        XCTAssertEqual(session.activeSet?.name, "S0")
        _ = session.handleKey(.digit(4))  // digits still pick the hot ten
        XCTAssertEqual(session.activeSet?.name, "S4")

        // 'S' bakes the arrangement into the active set's pool entry, slotted or not.
        _ = session.handleKey(.poolNext)  // S5
        for _ in 0..<6 { _ = session.handleKey(.poolNext) }  // S6..S9, S0, PoolA
        XCTAssertEqual(session.activeSet?.name, "PoolA")
        _ = session.handleKey(.c)
        _ = session.handleKey(.S)
        XCTAssertTrue(lines.take().contains("saved color set PoolA"))
        let entry = store.loadColorSetFile().sets.first { $0.name == "PoolA" }!
        XCTAssertNil(entry.slot)
        XCTAssertEqual(entry.colors, [grey(100)[0], grey(100)[1], grey(100)[3], grey(100)[2]])
        // Arrangements are remembered per set: S1 untouched, PoolA now at arrangement 1 of its baked colors.
        _ = session.handleKey(.digit(1))
        XCTAssertEqual(session.palette[0], RGB(hex: "#0A0A0A"))
    }

    // MARK: PT-34 a look carries its color set; n/p apply it (R-K5, R-B2)

    func testLookCarriesItsColorSetAndCycleAppliesIt() throws {
        let lines = Lines()
        let store = try reviewStore()
        let session = makeSession(store, lines: lines, select: odcaFile(store, name: "saver.odca"))
        _ = session.handleKey(.digit(3))  // S3
        _ = session.handleKey(.c)  // arranged (0,1,3,2)
        let rule = session.automaton.rule
        _ = lines.take()
        _ = session.handleKey(.S)
        XCTAssertTrue(lines.take().contains("added look 1/1"))
        let looks = Store.loadOdcaFile(session.selectFile!)!
        XCTAssertEqual(looks.count, 1)
        XCTAssertEqual(looks[0].colorset, "S3")
        XCTAssertEqual(looks[0].colors, ["#1E1E1E", "#1F1F1F", "#212121", "#202020"])

        // Change rule and colors, then browse: the look brings its colors back,
        // and the unsaved slot brings back the set that was showing with the unsaved rule.
        _ = session.handleKey(.m)
        let mutant = session.automaton.rule
        _ = session.handleKey(.digit(7))  // S7 showing with the unsaved (mutant) rule
        XCTAssertEqual(session.unsavedSet?.name, "S3")  // captured when the mutant arrived
        _ = session.handleKey(.n)
        XCTAssertEqual(session.automaton.rule, rule)
        XCTAssertEqual(session.palette.map(\.r), [0x1E, 0x1F, 0x21, 0x20])
        XCTAssertTrue(lines.take().contains("look 1/1 S3"))
        _ = session.handleKey(.n)  // back to the unsaved slot: mutant with S3 (as captured)
        XCTAssertEqual(session.automaton.rule, mutant)
        XCTAssertEqual(session.palette[0], RGB(hex: "#1E1E1E"))
    }
}
