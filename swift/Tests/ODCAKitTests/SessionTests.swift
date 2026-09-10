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
    func odcaFile(_ store: Store, rules: [Rule] = [], name: String = "pairs.odca") -> URL {
        let url = store.stateDir.deletingLastPathComponent().appendingPathComponent(name)
        if !rules.isEmpty {
            let d = Store.defaultColorSets[1]!
            Store.saveOdcaFile(rules.map { Pair(rule: $0.id, colorset: d.name, colors: d.colors) }, to: url)
        }
        return url
    }

    /// A session whose terminal output is captured into `lines`.
    func makeSession(_ store: Store, seed: UInt64 = 1, lines: Lines? = nil,
                     review: Bool = false, select: URL? = nil, play: URL? = nil, show: [Segment]? = nil,
                     shuffle: Bool = false, longest: Bool = false,
                     initialDelay: Double = Session.initialDelay,
                     playTimeout: Double = Session.playTimeout, playGrace: Double = Session.playGrace) -> Session {
        let sink: (String) -> Void = lines.map { l in { l.all.append($0) } } ?? { print($0) }
        return Session(cols: 32, rows: 16, store: store,
                       search: CandidateSearch(workers: 0), rng: Xoshiro256(seed: seed),
                       reviewMode: review, selectFile: select,
                       show: show ?? play.map { try! Show.load([$0]) }, shuffle: shuffle, longest: longest,
                       initialDelay: initialDelay, playTimeout: playTimeout, playGrace: playGrace, output: sink)
    }

    func testWatchdogAndGraceAreConstructionParameters() throws {  // PT-31, R-X2, R-X3
        let lines = Lines()
        let store = try reviewStore()
        let file = odcaFile(store, name: "saver.odca")
        Store.saveOdcaFile([Pair(rule: allProducible.id, colorset: "A", colors: grey(10)),
                            Pair(rule: allProducible.id, colorset: "B", colors: grey(20))], to: file)
        let session = makeSession(store, lines: lines, play: file, playTimeout: 20, playGrace: 10)
        _ = session.handleKey(.a)  // only the clocks transition
        session.tick(19)
        XCTAssertEqual(session.pairIndex, 0)
        session.tick(1.5)  // 20.5 s: the watchdog has expired and the grace period is long satisfied
        XCTAssertEqual(session.pairIndex, 1)
        XCTAssertTrue(lines.take().contains("pair 2/2 B (timeout)"))
        session.tick(15)
        _ = session.handleKey(.i)  // 15 s in: the grace period restarts, the watchdog does not
        session.tick(6)  // 21 s: expired, but only 6 s since the re-seed
        XCTAssertEqual(session.pairIndex, 1)
        session.tick(4.5)  // 25.5 s: 10.5 s since the re-seed
        XCTAssertEqual(session.pairIndex, 0)
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
        // A non-empty file opens on pair 1 with the unsaved slot empty (R-W1) ...
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertNil(session.unsavedRule)
        XCTAssertEqual(session.automaton.rule, saved[0])
        _ = session.handleKey(.r)  // ... until r fills it (m on a pair is an edit of it, 3.16.0)
        let first = session.automaton.rule
        XCTAssertNil(session.pairIndex)
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
        XCTAssertNil(session.pairIndex)
        XCTAssertEqual(session.unsavedRule, mutant)
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, saved[0])
        XCTAssertTrue(session.handleKey(.p))
        XCTAssertEqual(session.automaton.rule, mutant)
    }

    func testCycleStartupOnFirstPair() throws {  // PT-10a
        let saved = fourSaved
        let store = try makeStore(currentRule: saved[2])
        let session = makeSession(store, select: odcaFile(store, rules: saved))
        XCTAssertEqual(session.pairIndex, 0)
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
        XCTAssertEqual(session.pairs, [])
        _ = lines.take()
        XCTAssertTrue(session.handleKey(.n))
        XCTAssertEqual(session.automaton.rule, outside)
        XCTAssertTrue(lines.take().contains("no pairs"))
        let base = makeSession(try makeStore())  // no program: n/p have nothing to cycle
        let rule = base.automaton.rule
        XCTAssertTrue(base.handleKey(.n))
        XCTAssertEqual(base.automaton.rule, rule)
        XCTAssertNil(base.pairIndex)
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
        let index = session.pairIndex
        for key: Session.Key in [.r, .m, .u, .i, .n, .p, .a, .plus, .minus] {
            XCTAssertTrue(session.handleKey(key))
        }
        XCTAssertEqual(session.automaton.rule, rule)
        XCTAssertEqual(session.automaton.cells, cells)
        XCTAssertEqual(session.delay, delay)
        XCTAssertEqual(session.pairIndex, index)
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
        XCTAssertNil(session.pairIndex)
        XCTAssertEqual(session.unsavedRule, session.automaton.rule)
        XCTAssertTrue(lines.take().contains("odca saver.odca: 0 pairs"))
        let rule0 = session.automaton.rule
        _ = session.handleKey(.n)
        XCTAssertTrue(lines.take().contains("no pairs"))

        _ = session.handleKey(.digit(3))  // S3 = grey(30)
        _ = session.handleKey(.c)  // arranged (0,1,3,2)
        _ = session.handleKey(.s)  // on the unsaved slot: s appends, as S would (R-W4)
        var out = lines.take()
        XCTAssertTrue(out.contains("added pair 1/1") && out.contains("saved 1 pair to saver.odca"))
        XCTAssertNil(session.pairIndex)  // the position is unchanged
        XCTAssertEqual(Store.loadOdcaFile(file),
                       [Pair(name: "pair-0000", rule: rule0.id, colorset: "S3", colors: ["#1E1E1E", "#1F1F1F", "#212121", "#202020"])])

        _ = session.handleKey(.m)
        let rule1 = session.automaton.rule
        _ = session.handleKey(.poolNext)  // from S3 to S4
        XCTAssertTrue(lines.take().contains("color set S4"))
        _ = session.handleKey(.S)  // append a copy of the screen
        XCTAssertEqual(Store.loadOdcaFile(file)!.count, 2)
        XCTAssertNil(session.pairIndex)

        let gBefore = session.automaton.generation
        _ = session.handleKey(.n)  // pair 1: rule0, S3 arranged, and a screenful at once
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertEqual(session.automaton.rule, rule0)
        XCTAssertEqual(session.automaton.generation, 0)  // R-W8: a fresh field, scrolled in
        XCTAssertEqual(session.palette.map(\.r), [0x1E, 0x1F, 0x21, 0x20])
        XCTAssertTrue(lines.take().contains("pair 1/2 pair-0000 S3"))

        _ = session.handleKey(.digit(5))
        _ = session.handleKey(.s)  // on a pair: rewrite its color set in place, rule kept
        out = lines.take()
        XCTAssertTrue(out.contains("saved pair 1/2") && out.contains("saved 2 pairs to saver.odca"))
        var saved = Store.loadOdcaFile(file)!
        XCTAssertEqual(saved[0].rule, rule0.id)
        XCTAssertEqual(saved[0].colorset, "S5")
        XCTAssertEqual(saved[0].colors, grey(50))
        XCTAssertEqual(saved[1].rule, rule1.id)

        _ = session.handleKey(.n)  // pair 2
        XCTAssertEqual(session.automaton.rule, rule1)
        XCTAssertEqual(session.pairIndex, 1)
        _ = session.handleKey(.n)  // the unsaved slot: the mutant with the set it arrived with
        XCTAssertTrue(lines.take().contains("unsaved rule"))
        XCTAssertNil(session.pairIndex)
        XCTAssertEqual(session.automaton.rule, rule1)
        _ = session.handleKey(.X)  // nothing under review: no-op
        XCTAssertEqual(Store.loadOdcaFile(file)!.count, 2)
        _ = session.handleKey(.p)  // back to pair 2
        _ = session.handleKey(.X)  // delete the last: shows the previous
        out = lines.take()
        XCTAssertTrue(out.contains("deleted pair 2/2") && out.contains("saved 1 pair to saver.odca"))
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertEqual(Store.loadOdcaFile(file)!.count, 1)
        _ = session.handleKey(.X)
        XCTAssertNil(session.pairIndex)
        XCTAssertEqual(Store.loadOdcaFile(file), [])
        XCTAssertEqual(session.unsavedRule, session.automaton.rule)  // keeps running as the unsaved rule

        session.finish()  // exit writes the file
        XCTAssertEqual(Store.loadOdcaFile(file), [])
        Store.saveOdcaFile([Pair(rule: rule1.id, colorset: "S7", colors: grey(70))], to: file)
        let again = makeSession(store, select: file)
        XCTAssertEqual(again.pairIndex, 0)
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
        XCTAssertEqual(session.pairs, [])
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
            Pair(rule: rule, colorset: set, colors: grey(Int(set.dropFirst())! * 10))
        }
        Store.saveOdcaFile(original, to: file)

        let session = makeSession(store, lines: lines, select: file)
        XCTAssertEqual(session.viewOrder, [0, 1, 2, 3, 4])
        XCTAssertFalse(session.grouped)
        _ = lines.take()
        _ = session.handleKey(.R)  // grouped by rule: A A B B C
        var out = lines.take()
        XCTAssertTrue(out.contains("pair order grouped by rule"))
        XCTAssertTrue(session.grouped)
        XCTAssertEqual(session.viewOrder, [0, 2, 1, 4, 3])
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertEqual(session.viewPosition, 0)  // the pair under review is kept
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
        XCTAssertTrue(out.contains("pair 2/5 pair-0002 S3") && !out.contains("rule group"))
        _ = session.handleKey(.n)
        out = lines.take()
        XCTAssertTrue(out.contains("--- rule group 2/3 ---") && out.contains("pair 3/5 pair-0001 S2"))
        XCTAssertEqual(session.pairIndex, 1)  // file position of S2

        _ = session.handleKey(.S)  // append a B pair: end of file, but grouped with B in the view
        XCTAssertEqual(session.pairs.count, 6)
        XCTAssertEqual(session.viewOrder, [0, 2, 1, 4, 5, 3])
        XCTAssertEqual(session.viewPosition, 2)  // still on S2
        _ = session.handleKey(.n)  // S5
        _ = session.handleKey(.n)  // the appended pair, same group: no marker
        out = lines.take()
        XCTAssertTrue(out.contains("pair 5/6") && !out.contains("rule group"))
        XCTAssertEqual(session.pairIndex, 5)
        _ = session.handleKey(.n)  // C
        XCTAssertTrue(lines.take().contains("--- rule group 3/3 ---"))
        XCTAssertEqual(session.pairIndex, 3)

        _ = session.handleKey(.digit(7))  // modify C's color set in place
        _ = session.handleKey(.s)
        var saved = Store.loadOdcaFile(file)!
        XCTAssertEqual(saved.map(\.colorset), ["S1", "S2", "S3", "S7", "S5", "S2"])  // file order kept
        XCTAssertEqual(saved[5].rule, b)

        _ = session.handleKey(.p)  // back to the appended pair (view 5/6)
        _ = session.handleKey(.X)  // delete it: file loses its last entry
        saved = Store.loadOdcaFile(file)!
        XCTAssertEqual(saved.map(\.colorset), ["S1", "S2", "S3", "S7", "S5"])
        XCTAssertEqual(session.viewPosition, 4)  // the pair now at that view position: C
        XCTAssertEqual(session.pairIndex, 3)
        _ = session.handleKey(.R)  // back to file order, still on S7
        XCTAssertTrue(lines.take().contains("pair order file order"))
        XCTAssertEqual(session.viewOrder, [0, 1, 2, 3, 4])
        XCTAssertEqual(session.viewPosition, 3)
    }

    // MARK: PT-31 odca (R-X)

    func testPlaysLooksInOrderAndLoops() throws {
        let lines = Lines()
        let store = try reviewStore()
        let file = odcaFile(store, name: "saver.odca")
        let dies = allZero  // repeating (period 1) within a screenful
        Store.saveOdcaFile([Pair(rule: dies.id, colorset: "A", colors: grey(10)),
                            Pair(rule: dies.id, colorset: "B", colors: grey(20))], to: file)
        let session = makeSession(store, lines: lines, play: file)
        XCTAssertTrue(session.playMode && !session.selectMode && !session.reviewMode)
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertEqual(session.automaton.rule, dies)
        XCTAssertEqual(session.palette[0], RGB(hex: "#0A0A0A"))
        XCTAssertEqual(session.automaton.generation, 0)  // freshly seeded
        var out = lines.take()
        XCTAssertTrue(out.contains("odca saver.odca: 2 pairs") && out.contains("pair 1/2 A"))
        XCTAssertFalse(out.contains("("))  // no reason on the first pair

        // Before the watchdog expires, boredom re-seeds in place: the pair keeps its screen time.
        for _ in 0..<17 { session.tick(1.0 / 60.0) }
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertEqual(session.automaton.generation, 0)  // re-seeded
        out = lines.take()
        XCTAssertTrue(out.contains("auto-init (repeating (period 1))") && !out.contains("pair 2/2"))

        // Run out the watchdog without firings (auto-init off), re-seed by hand just before
        // expiry so the grace period is unsatisfied at expiry, then re-arm: the next firing
        // transitions instead of re-seeding in place, carrying its reason.
        _ = session.handleKey(.a)
        session.tick(110)
        XCTAssertEqual(session.pairIndex, 0)
        _ = session.handleKey(.i)  // grace restarts; the watchdog does not
        XCTAssertEqual(session.playElapsed, 110, accuracy: 1)
        _ = session.handleKey(.a)
        _ = lines.take()
        session.tick(10)  // the watchdog expires during this tick; boredom fires within it
        XCTAssertEqual(session.pairIndex, 1)
        XCTAssertLessThan(session.playElapsed, 1)  // the new pair's clock started inside the tick
        XCTAssertEqual(session.palette[0], RGB(hex: "#141414"))
        // R-X5: rows from pair A keep A's colors below the boundary; B's rows above it.
        let firstB = session.rowPalettes.firstIndex(of: 1)!
        XCTAssertEqual(session.rowPalettes[firstB - 1], 0)
        XCTAssertEqual(session.rowPalettes.last, 1)
        XCTAssertEqual(session.color(row: firstB - 1, col: 0), RGB(hex: "#0A0A0A"))  // state 0 under A
        XCTAssertEqual(session.paletteTable[0], RGB(hex: "#0A0A0A"))
        XCTAssertEqual(session.paletteTable[4], RGB(hex: "#141414"))
        out = lines.take()
        XCTAssertTrue(out.contains("pair 2/2 B (repeating (period 1))"))

        // Looping: one long tick expires the watchdog and the firings inside it wrap to pair 1.
        session.tick(Session.playTimeout)
        XCTAssertEqual(session.pairIndex, 0)
        out = lines.take()
        XCTAssertTrue(out.contains("pair 1/2 A (repeating (period 1))"))
        XCTAssertFalse(out.contains("pair 2/2"))

        // R-X6: N/P (and n/p) move through the pairs by hand, wrapping, with a fresh seed each time.
        session.tick(1.0 / 60.0)
        _ = session.handleKey(.N)
        XCTAssertEqual(session.pairIndex, 1)
        XCTAssertEqual(session.automaton.generation, 0)
        XCTAssertTrue(lines.take().contains("pair 2/2 B (next)"))
        _ = session.handleKey(.n)  // wraps
        XCTAssertEqual(session.pairIndex, 0)
        _ = session.handleKey(.space)
        _ = session.handleKey(.P)  // live while paused; wraps backward
        XCTAssertEqual(session.pairIndex, 1)
        XCTAssertTrue(lines.take().contains("pair 2/2 B (previous)"))
        _ = session.handleKey(.space)
        for key: Session.Key in [.s, .S, .X] { _ = session.handleKey(key) }  // odca never writes the file
        XCTAssertEqual(Store.loadOdcaFile(file)!.count, 2)
    }

    func testPlayWatchdogAndGracePeriod() throws {
        let lines = Lines()
        let store = try reviewStore()
        let file = odcaFile(store, name: "saver.odca")
        Store.saveOdcaFile([Pair(rule: allProducible.id, colorset: "A", colors: grey(10)),
                            Pair(rule: allProducible.id, colorset: "B", colors: grey(20))], to: file)
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
        XCTAssertEqual(session.pairIndex, 0)
        session.tick(39.5)
        XCTAssertEqual(session.pairIndex, 0)
        session.tick(1.0)  // 60 s since the re-seed: transition
        XCTAssertEqual(session.pairIndex, 1)
        XCTAssertTrue(lines.take().contains("pair 2/2 B (timeout)"))
        XCTAssertEqual(session.playElapsed, 0, accuracy: 1e-9)

        // A quiet pair transitions as soon as the watchdog expires (grace long satisfied).
        session.tick(119.5)
        XCTAssertEqual(session.pairIndex, 1)
        session.tick(1.0)
        XCTAssertEqual(session.pairIndex, 0)
    }

    func testShuffleDrawsAFreshOrderOfTheFiles() throws {  // PT-36
        let lines = Lines()
        let store = try reviewStore()
        let b = try Rule(id: String(repeating: "1", count: 20)), c = try Rule(id: String(repeating: "2", count: 20))
        let files = [odcaFile(store, rules: [allProducible, b], name: "a.odca"),
                     odcaFile(store, rules: [c], name: "b.odca"),
                     odcaFile(store, rules: [allZero, b, c], name: "c.odca")]
        let show = try Show.load(files)
        let session = makeSession(store, lines: lines, show: show, shuffle: true)
        XCTAssertTrue(session.shuffle)
        var out = lines.take()
        XCTAssertTrue(out.contains("odca a.odca: 2 pairs\nodca b.odca: 1 pairs\nodca c.odca: 3 pairs\n"), out)
        XCTAssertTrue(out.contains("playing "))
        XCTAssertLessThan(out.range(of: "playing ")!.lowerBound, out.range(of: "pair 1/")!.lowerBound)  // R-O13
        var played = [[session.playSegment!, session.pairIndex!]]
        for _ in 0..<59 { _ = session.handleKey(.N); played.append([session.playSegment!, session.pairIndex!]) }  // ten passes
        let sizes = [2, 1, 3]
        var orders = Set<[Int]>()
        for p in 0..<10 {
            let onePass = Array(played[(6 * p)..<(6 * p + 6)])
            let order = onePass.filter { $0[1] == 0 }.map { $0[0] }  // the files, in the order the pass plays them
            XCTAssertEqual(order.sorted(), [0, 1, 2])  // every file once
            let expected = order.flatMap { seg in (0..<sizes[seg]).map { [seg, $0] } }
            XCTAssertEqual(onePass, expected)  // the pairs of a file in file order, the file played whole
            orders.insert(order)
        }
        for p in 1..<10 { XCTAssertNotEqual(played[6 * p - 1][0], played[6 * p][0]) }  // never the same file twice running
        XCTAssertGreaterThan(orders.count, 1)  // fresh draws
        out = lines.take()
        XCTAssertEqual(out.components(separatedBy: "playing ").count - 1, 29)  // every file entry announced (the first read above)
        _ = session.handleKey(.P)  // back one within the pass
        XCTAssertEqual([session.playSegment!, session.pairIndex!], played[played.count - 2])
        let plain = makeSession(store, show: show)
        XCTAssertFalse(plain.shuffle)
        XCTAssertEqual(plain.playOrder.map { [$0.segment, $0.index] }, [[0, 0], [0, 1], [1, 0], [2, 0], [2, 1], [2, 2]])
        // One file with pairs among empty ones: it plays on, and shuffling changes nothing that shows.
        let empty = odcaFile(store, name: "empty.odca")
        try "{\"pairs\": []}".write(to: empty, atomically: true, encoding: .utf8)
        let lone = makeSession(store, show: try Show.load([empty, files[1], empty]), shuffle: true)
        for _ in 0..<4 { _ = lone.handleKey(.N) }
        XCTAssertEqual([lone.playSegment!, lone.pairIndex!], [1, 0])
        // A single file: `playing` is never printed, and every pass is the file's order.
        let single = makeSession(store, lines: lines, show: try Show.load([files[2]]), shuffle: true)
        _ = lines.take()
        for _ in 0..<6 { _ = single.handleKey(.N) }
        out = lines.take()
        XCTAssertFalse(out.contains("playing"))
        XCTAssertEqual(single.pairIndex, 0)
    }

    func testShuffleDrawsAFreshOrderOfAScriptsPairs() throws {  // PT-39
        let lines = Lines()
        let store = try reviewStore()
        let a = allProducible, b = try Rule(id: String(repeating: "1", count: 20)), c = try Rule(id: String(repeating: "2", count: 20))
        let x = grey(10), y = grey(20), z = grey(30)
        let pairs = [Pair(rule: a.id, colorset: "X", colors: x), Pair(rule: a.id, colorset: "Y", colors: y),
                     Pair(rule: b.id, colorset: "X'", colors: x.reversed()), Pair(rule: b.id, colorset: "Z", colors: z),
                     Pair(rule: c.id, colorset: "Y", colors: y), Pair(rule: c.id, colorset: "Z", colors: z)]
        let file = odcaFile(store, name: "six.odca")
        Store.saveOdcaFile(pairs, to: file)
        let script = file.deletingLastPathComponent().appendingPathComponent("six.play")
        try "import six.odca\nshuffle\n".write(to: script, atomically: true, encoding: .utf8)
        let session = makeSession(store, lines: lines, show: try Show.load([script]))
        XCTAssertFalse(session.shuffle)  // the script asked, not the command line
        XCTAssertTrue(lines.take().contains("odca six.play: 6 pairs, shuffled"))  // R-O13
        var played = [session.pairIndex!]
        for _ in 0..<59 { _ = session.handleKey(.N); played.append(session.pairIndex!) }  // ten passes
        for p in 0..<10 {
            XCTAssertEqual(Array(played[(6 * p)..<(6 * p + 6)]).sorted(), Array(0..<6))  // every pass: every pair once
        }
        for (i, j) in zip(played, played.dropFirst()) {  // never the same rule or color set in a row, seams included
            XCTAssertNotEqual(pairs[i].rule, pairs[j].rule, "\(i) then \(j)")
            XCTAssertNotEqual(pairs[i].colors.sorted(), pairs[j].colors.sorted(), "\(i) then \(j)")
        }
        _ = session.handleKey(.P)  // back one within the pass
        XCTAssertEqual(session.pairIndex, played[played.count - 2])
        try "import six.odca\nplay\n".write(to: script, atomically: true, encoding: .utf8)  // plain play: file order
        let plain = makeSession(store, lines: lines, show: try Show.load([script]))
        XCTAssertEqual(plain.playOrder.map { $0.index }, Array(0..<6))
        XCTAssertFalse(lines.take().contains(", shuffled"))
        // No order can avoid a repeat: the requirement is dropped and the show goes on.
        Store.saveOdcaFile([Pair(rule: a.id, colorset: "X", colors: x), Pair(rule: a.id, colorset: "Y", colors: y)], to: file)
        try "import six.odca\nshuffle\n".write(to: script, atomically: true, encoding: .utf8)
        let small = makeSession(store, show: try Show.load([script]))
        var pair = [small.pairIndex!]
        for _ in 0..<5 { _ = small.handleKey(.N); pair.append(small.pairIndex!) }
        for i in stride(from: 0, to: 6, by: 2) { XCTAssertEqual(Array(pair[i..<(i + 2)]).sorted(), [0, 1]) }
    }

    func testAShuffledScriptKeepsItsSeamWithTheOtherFiles() throws {  // PT-39
        let store = try reviewStore()
        let a = try Rule(id: String(repeating: "1", count: 20)), b = try Rule(id: String(repeating: "2", count: 20))
        let x = grey(10), y = grey(20)
        // The plain file ends on rule b with colors y; the shuffled file holds one
        // pair on each, so only b-then-a, y-then-x can open its pass.
        let plainFile = odcaFile(store, name: "plain.odca")
        Store.saveOdcaFile([Pair(rule: b.id, colorset: "Y", colors: y)], to: plainFile)
        let shuffledFile = odcaFile(store, name: "two.odca")
        Store.saveOdcaFile([Pair(rule: b.id, colorset: "Y", colors: y),
                            Pair(rule: a.id, colorset: "X", colors: x)], to: shuffledFile)
        let script = shuffledFile.deletingLastPathComponent().appendingPathComponent("two.play")
        try "import two.odca\nshuffle\n".write(to: script, atomically: true, encoding: .utf8)
        let session = makeSession(store, show: try Show.load([plainFile, script]))
        for _ in 0..<20 {  // the clashing pair never opens the file
            XCTAssertEqual(session.playOrder.dropFirst().map { [$0.segment, $0.index] }, [[1, 1], [1, 0]])
            _ = session.handleKey(.N)
        }
    }

    func testArrivalUsesTheLongestRecordedSeedAtTheScreenWidth() throws {  // PT-42, R-X4
        let store = try reviewStore()
        let file = odcaFile(store, rules: [allZero, allProducible], name: "seeded.odca")
        let best = [UInt8](repeating: 3, count: 32), second = [UInt8](repeating: 2, count: 32)
        let wrongWidth = [UInt8](repeating: 1, count: 33)
        Store.saveOdcaFile(Store.loadOdcaFile(file)!, seeds: [
            allZero.id: [32: [Seed(row: second, generations: 5, end: "state 1 extinct"),
                              Seed(row: best, generations: 9, end: "survived")],
                         33: [Seed(row: wrongWidth, generations: 99, end: "survived")]],
        ], to: file)
        let session = makeSession(store, show: try Show.load([file]))
        XCTAssertEqual(session.automaton.cells, best)  // pair 1: its longest seed at 32 cells, not a random row
        XCTAssertEqual(session.automaton.generation, 0)
        _ = session.handleKey(.N)  // pair 2 has no seeds: random
        XCTAssertNotEqual(session.automaton.cells, best)
        XCTAssertEqual(session.automaton.cells.count, 32)
        _ = session.handleKey(.N)  // back to pair 1: the seed again
        XCTAssertEqual(session.automaton.cells, best)
        _ = session.handleKey(.i)  // a manual re-seed is random, as ever
        XCTAssertNotEqual(session.automaton.cells, best)
        XCTAssertTrue(session.resize(cols: 33, rows: 16))
        _ = session.handleKey(.N)
        _ = session.handleKey(.N)  // pair 1 at 33 cells: that width's seed
        XCTAssertEqual(session.automaton.cells, wrongWidth)
        // A script show carries the seeds of every file it imports.
        let script = file.deletingLastPathComponent().appendingPathComponent("seeded.play")
        try "import seeded.odca\nplay\n".write(to: script, atomically: true, encoding: .utf8)
        let scripted = makeSession(store, show: try Show.load([script]))
        XCTAssertEqual(scripted.automaton.cells, best)
    }

    /// A block of 3s in a field of 1s under killsThree: the block loses a cell
    /// at each edge per generation, so a block of 2k dies at generation k.
    func block(_ threes: Int, in width: Int) -> [UInt8] {
        [UInt8](repeating: 1, count: (width - threes) / 2) + [UInt8](repeating: 3, count: threes)
            + [UInt8](repeating: 1, count: width - threes - (width - threes) / 2)
    }

    func testLongestPlaysTheRecordedSeedsRankByRank() throws {  // PT-44, R-X8, R-O13
        let lines = Lines()
        let store = try reviewStore()
        let file = odcaFile(store, name: "seeded.odca")
        let a = killsThree, b = allProducible, c = allZero
        Store.saveOdcaFile([Pair(rule: a.id, colorset: "A", colors: grey(10)),
                            Pair(rule: b.id, colorset: "B", colors: grey(20)),
                            Pair(rule: c.id, colorset: "C", colors: grey(30))], seeds: [
            a.id: [32: [Seed(row: block(16, in: 32), generations: 8, end: "state 3 extinct"),
                        Seed(row: block(12, in: 32), generations: 6, end: "state 3 extinct")],
                   33: [Seed(row: block(16, in: 33), generations: 8, end: "state 3 extinct")]],
            b.id: [32: [Seed(row: [UInt8](repeating: 0, count: 32), generations: 100_000, end: Seed.survived),
                        Seed(row: [UInt8](repeating: 2, count: 32), generations: 5, end: "state 1 extinct")]],
        ], to: file)
        let show = try Show.load([file])
        XCTAssertThrowsError(try Show.seedWidth(show, cells: nil)) {  // two widths: --cells must choose
            XCTAssertEqual($0 as? ShowError, ShowError("seeds at 32, 33 cells: choose one with --cells"))
        }
        XCTAssertEqual(try Show.seedWidth(show, cells: 32), 32)
        XCTAssertThrowsError(try Show.seedWidth(show, cells: 40)) {
            XCTAssertEqual($0 as? ShowError, ShowError("no seeds at 40 cells (32, 33)"))
        }
        let survivors = odcaFile(store, name: "survivors.odca")
        Store.saveOdcaFile([Pair(rule: b.id, colorset: "B", colors: grey(20))],
                           seeds: [b.id: [32: [Seed(row: [UInt8](repeating: 0, count: 32), generations: 9, end: Seed.survived)]]],
                           to: survivors)
        XCTAssertThrowsError(try Show.seedWidth(try Show.load([survivors]), cells: nil)) {
            XCTAssertEqual($0 as? ShowError, ShowError("no seeds to play"))  // survivors are not played
        }

        let session = makeSession(store, lines: lines, show: show, longest: true, playTimeout: 1, playGrace: 1)
        XCTAssertTrue(session.longest && session.playMode)
        var out = lines.take()
        XCTAssertTrue(out.contains("odca seeded.odca: 3 pairs, 3 seeds at 32 cells"), out)
        XCTAssertTrue(out.hasSuffix("pair 1/3 A, seed 1/2, 8 generations"), out)
        // Every pair's longest, then every pair's second: A1, B1 (its survivor left out), A2; C has none.
        XCTAssertEqual(session.playOrder.map { [$0.segment, $0.index, $0.seed!] }, [[0, 0, 0], [0, 1, 0], [0, 0, 1]])
        XCTAssertEqual(session.automaton.cells, block(16, in: 32))
        XCTAssertEqual(session.automaton.rule, a)
        // The rule keys and auto-init are inert; the colors keys are not.
        for key in [Session.Key.r, .m, .u, .U, .a] { _ = session.handleKey(key) }
        XCTAssertEqual(session.automaton.rule, a)
        XCTAssertTrue(session.autoInit)
        XCTAssertTrue(session.undoStack.isEmpty)
        _ = session.handleKey(.digit(2))
        XCTAssertEqual(session.activeSet?.name, "S2")
        // The width is the seeds'; only the height follows the window.
        XCTAssertTrue(session.resize(cols: 40, rows: 20))
        XCTAssertEqual(session.cols, 32)
        XCTAssertEqual(session.rows, 20)
        XCTAssertTrue(lines.take().contains("resized 32x20"))
        XCTAssertFalse(session.resize(cols: 48, rows: 20))
        // `i` restarts the seed on screen (once resumed: it is not live while paused, R-K10).
        _ = session.handleKey(.space)
        for _ in 0..<3 { _ = session.handleKey(.ret) }
        XCTAssertNotEqual(session.automaton.cells, block(16, in: 32))
        _ = session.handleKey(.space)
        _ = session.handleKey(.i)
        XCTAssertEqual(session.automaton.cells, block(16, in: 32))
        XCTAssertEqual(session.automaton.generation, 0)
        // No clocks: with a one-second watchdog and grace period, six quiet
        // seconds (the delay at its slowest, no generation computed) change nothing.
        for _ in 0..<12 { _ = session.handleKey(.minus) }
        for _ in 0..<3 { session.tick(2) }
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertEqual(session.automaton.generation, 0)
        XCTAssertFalse(lines.take().contains("timeout"))
        // The seed plays to its extinction (generation 8), and a screenful (20
        // rows) past it (R-A2) the next seed takes over: at generation 27; no
        // re-seed in place.
        _ = session.handleKey(.space)
        for _ in 0..<26 { _ = session.handleKey(.ret) }
        XCTAssertEqual(session.pairIndex, 0)
        _ = session.handleKey(.ret)
        XCTAssertEqual(session.pairIndex, 1)
        out = lines.take()
        XCTAssertTrue(out.contains("pair 2/3 B, seed 1/1, 5 generations (state 3 extinct)"), out)
        XCTAssertFalse(out.contains("auto-init"), out)
        XCTAssertEqual(session.automaton.cells, [UInt8](repeating: 2, count: 32))
        XCTAssertEqual(session.automaton.generation, 0)
        // N and P walk the items, wrapping; the third is A's second seed.
        _ = session.handleKey(.N)
        XCTAssertTrue(lines.take().contains("pair 1/3 A, seed 2/2, 6 generations (next)"))
        XCTAssertEqual(session.automaton.cells, block(12, in: 32))
        _ = session.handleKey(.space)  // n and p are not live while paused (R-K10); N and P are
        _ = session.handleKey(.n)
        XCTAssertTrue(lines.take().contains("pair 1/3 A, seed 1/2, 8 generations (next)"))
        _ = session.handleKey(.p)
        XCTAssertTrue(lines.take().contains("seed 2/2, 6 generations (previous)"))
    }

    func testLongestShuffleKeepsRulesAndColorsApart() throws {  // PT-44, R-X8
        let store = try reviewStore()
        let file = odcaFile(store, name: "seeded.odca")
        let rules = [allProducible, try Rule(id: String(repeating: "1", count: 20)), try Rule(id: String(repeating: "2", count: 20))]
        var seeds: Seeds = [:]
        for (i, rule) in rules.enumerated() {
            seeds[rule.id] = [32: [Seed(row: [UInt8](repeating: UInt8(i), count: 32), generations: 9, end: "x"),
                                   Seed(row: [UInt8](repeating: 3, count: 32), generations: 4, end: "x")]]
        }
        Store.saveOdcaFile(rules.enumerated().map { Pair(rule: $1.id, colorset: "S\($0)", colors: grey(10 * $0)) },
                           seeds: seeds, to: file)
        let session = makeSession(store, show: try Show.load([file]), shuffle: true, longest: true)
        var played = [[session.pairIndex!, session.playOrder[session.playPosition!].seed!]]
        for _ in 0..<59 { _ = session.handleKey(.N); played.append([session.pairIndex!, session.playOrder[session.playPosition!].seed!]) }
        var orders = Set<[[Int]]>()
        for p in 0..<10 {
            let pass = Array(played[(6 * p)..<(6 * p + 6)])
            XCTAssertEqual(pass.sorted { $0.lexicographicallyPrecedes($1) }, [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1]])
            orders.insert(pass)
        }
        for (x, y) in zip(played, played.dropFirst()) { XCTAssertNotEqual(x[0], y[0]) }  // never the same pair twice running
        XCTAssertGreaterThan(orders.count, 1)
        let plain = makeSession(store, show: try Show.load([file]), longest: true)
        XCTAssertEqual(plain.playOrder.map { [$0.index, $0.seed!] }, [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1]])
    }

    func testRowsKeepTheirColorsThroughQuickTransitions() throws {  // PT-31, R-X5
        let store = try reviewStore()
        let file = odcaFile(store, name: "saver.odca")
        Store.saveOdcaFile([Pair(rule: allZero.id, colorset: "A", colors: grey(10)),
                            Pair(rule: allZero.id, colorset: "B", colors: grey(20)),
                            Pair(rule: allZero.id, colorset: "C", colors: grey(30))], to: file)
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
        _ = session.handleKey(.N)  // pair 2, well within the screenful
        for _ in 0..<3 { session.tick(session.delay) }
        let rowsAB = session.history.count
        _ = session.handleKey(.N)  // pair 3: a third color set on one screen
        for _ in 0..<3 { session.tick(session.delay) }
        painted(0..<rowsA, grey(10))
        painted(rowsA..<rowsAB, grey(20))
        painted(rowsAB..<session.history.count, grey(30))
        XCTAssertEqual(session.paletteTable.count, 12)  // three palettes
        _ = session.handleKey(.N)  // back to pair 1: its palette is shared, not duplicated
        session.tick(session.delay)
        XCTAssertEqual(session.paletteTable.count, 12)
        // Many distinct palettes (arrangements of each set) pass the table's limit:
        // it is pruned to what remembered rows still use, and no row changes color.
        for i in 0..<(Session.paletteLimit + 10) {
            _ = session.handleKey(.N)  // the pair shows its baked colors, arrangement 1
            for _ in 0..<(i % 23 + 1) { _ = session.handleKey(.c) }  // then a different arrangement each time round
            session.tick(session.delay)
        }
        painted(0..<rowsA, grey(10))
        painted(rowsA..<rowsAB, grey(20))
        XCTAssertGreaterThan(session.paletteTable.count, 4 * Session.paletteLimit)
        XCTAssertLessThanOrEqual(session.paletteTable.count, 4 * session.history.count)
    }

    func testMutatingAPairSavesItAsANewPair() throws {  // PT-34, R-K3, R-W4
        let lines = Lines()
        let store = try reviewStore()
        let one = allZero, two = try Rule(id: String(repeating: "1", count: 20))
        let file = odcaFile(store, rules: [one, two], name: "saver.odca")
        let session = makeSession(store, lines: lines, select: file)
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertNil(session.unsavedRule)
        _ = session.handleKey(.digit(3))
        _ = lines.take()
        _ = session.handleKey(.s)  // colors only: the pair is rewritten in place
        XCTAssertTrue(lines.take().contains("saved pair 1/2"))
        XCTAssertEqual(Store.loadOdcaFile(file)![0], Pair(name: "pair-0000", rule: one.id, colorset: "S3", colors: grey(30)))
        _ = session.handleKey(.m)  // pair 1 is now changed: the position stays, the unsaved slot stays empty
        XCTAssertNotEqual(session.automaton.rule, one)
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertEqual(session.viewPosition, 0)
        XCTAssertNil(session.unsavedRule)
        _ = session.handleKey(.u)  // walked back, still on pair 1
        XCTAssertEqual(session.automaton.rule, one)
        XCTAssertEqual(session.pairIndex, 0)
        _ = session.handleKey(.m)
        let mutant = session.automaton.rule
        _ = session.handleKey(.digit(5))
        _ = lines.take()
        _ = session.handleKey(.s)  // a changed pair is saved as a new pair at the end; the kept rule survives
        XCTAssertTrue(lines.take().contains("added pair 3/3"))
        var pairs = Store.loadOdcaFile(file)!
        XCTAssertEqual(pairs.map(\.rule), [one.id, two.id, mutant.id])
        XCTAssertEqual(pairs[0].colorset, "S3")
        XCTAssertEqual(pairs[2].colorset, "S5")
        XCTAssertEqual(session.pairIndex, 2)  // and the position moved onto it
        XCTAssertEqual(session.viewPosition, 2)
        _ = session.handleKey(.U)  // nothing to unwind on the new pair
        XCTAssertEqual(session.automaton.rule, mutant)
        _ = session.handleKey(.digit(7))
        _ = session.handleKey(.s)  // colors again: refines the new pair in place
        XCTAssertTrue(lines.take().contains("saved pair 3/3"))
        pairs = Store.loadOdcaFile(file)!
        XCTAssertEqual(pairs.map(\.colorset), ["S3", "ODCA default", "S7"])
        _ = session.handleKey(.m)  // a further mutation, discarded by leaving the pair
        _ = session.handleKey(.n)
        _ = session.handleKey(.p)
        XCTAssertEqual(session.automaton.rule, mutant)
        XCTAssertEqual(session.pairIndex, 2)
        _ = session.handleKey(.r)  // a fresh rule is a new exploration: the unsaved slot, as before
        XCTAssertNil(session.pairIndex)
        XCTAssertEqual(session.unsavedRule, session.automaton.rule)
        _ = session.handleKey(.m)  // on the unsaved slot the mutant stays there
        XCTAssertNil(session.pairIndex)
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
        _ = session.handleKey(.U)  // all three at once, still on pair 1
        XCTAssertEqual(session.automaton.rule, one)
        XCTAssertEqual(session.pairIndex, 0)
        XCTAssertEqual(session.undoStack.count, depth)
        _ = session.handleKey(.U)  // nothing left since arriving here: a no-op
        XCTAssertEqual(session.automaton.rule, one)
        XCTAssertEqual(session.undoStack.count, depth)
        _ = session.handleKey(.n)  // pair 2 (one push); edits here unwind to pair 2, not further
        _ = session.handleKey(.m)
        _ = session.handleKey(.m)
        _ = session.handleKey(.U)
        XCTAssertEqual(session.automaton.rule, two)
        XCTAssertEqual(session.pairIndex, 1)
        XCTAssertEqual(session.undoStack.count, depth + 1)
        _ = session.handleKey(.r)  // the unsaved slot: U unwinds to the rule r brought
        let fresh = session.automaton.rule
        _ = session.handleKey(.m)
        _ = session.handleKey(.m)
        XCTAssertNotEqual(session.automaton.rule, fresh)
        _ = session.handleKey(.U)
        XCTAssertEqual(session.automaton.rule, fresh)
        XCTAssertNil(session.pairIndex)
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

    // MARK: PT-34 a pair carries its color set; n/p apply it (R-K5, R-B2)

    func testPairCarriesItsColorSetAndCycleAppliesIt() throws {
        let lines = Lines()
        let store = try reviewStore()
        let session = makeSession(store, lines: lines, select: odcaFile(store, name: "saver.odca"))
        _ = session.handleKey(.digit(3))  // S3
        _ = session.handleKey(.c)  // arranged (0,1,3,2)
        let rule = session.automaton.rule
        _ = lines.take()
        _ = session.handleKey(.S)
        XCTAssertTrue(lines.take().contains("added pair 1/1"))
        let pairs = Store.loadOdcaFile(session.selectFile!)!
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].colorset, "S3")
        XCTAssertEqual(pairs[0].colors, ["#1E1E1E", "#1F1F1F", "#212121", "#202020"])

        // Change rule and colors, then browse: the pair brings its colors back,
        // and the unsaved slot brings back the set that was showing with the unsaved rule.
        _ = session.handleKey(.m)
        let mutant = session.automaton.rule
        _ = session.handleKey(.digit(7))  // S7 showing with the unsaved (mutant) rule
        XCTAssertEqual(session.unsavedSet?.name, "S3")  // captured when the mutant arrived
        _ = session.handleKey(.n)
        XCTAssertEqual(session.automaton.rule, rule)
        XCTAssertEqual(session.palette.map(\.r), [0x1E, 0x1F, 0x21, 0x20])
        XCTAssertTrue(lines.take().contains("pair 1/1 pair-0000 S3"))
        _ = session.handleKey(.n)  // back to the unsaved slot: mutant with S3 (as captured)
        XCTAssertEqual(session.automaton.rule, mutant)
        XCTAssertEqual(session.palette[0], RGB(hex: "#1E1E1E"))
    }
}
