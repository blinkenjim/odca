import Foundation
import XCTest

@testable import ODCAKit

/// Layer 2 of TESTS.md: property tests PT-1..PT-8, PT-11, PT-12.
final class PropertyTests: XCTestCase {
    func tempStore() throws -> Store {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odca-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Store(
            stateDir: dir.appendingPathComponent("state"),
            keeperFile: dir.appendingPathComponent("interesting-rules.txt"))
    }

    // PT-1: mutation changes exactly one entry to a different valid state.
    func testMutationChangesExactlyOneEntry() {
        var rng = Xoshiro256(seed: 11)
        var rule = Rule.random(using: &rng)
        for _ in 0..<50 {
            let mutant = rule.mutated(using: &rng)
            let diffs = (0..<Rule.tableSize).filter { rule.states[$0] != mutant.states[$0] }
            XCTAssertEqual(diffs.count, 1)
            let i = diffs[0]
            XCTAssertLessThan(mutant.states[i], UInt8(Rule.stateCount))
            XCTAssertNotEqual(mutant.states[i], rule.states[i])
            rule = mutant
        }
    }

    // PT-2: random rules are valid.
    func testRandomRulesValid() {
        var rng = Xoshiro256(seed: 2)
        for _ in 0..<20 {
            let rule = Rule.random(using: &rng)
            XCTAssertEqual(rule.states.count, Rule.tableSize)
            XCTAssertTrue(rule.states.allSatisfy { $0 < UInt8(Rule.stateCount) })
        }
    }

    // PT-3: invalid construction fails cleanly.
    func testInvalidConstructionRejected() {
        var rng = Xoshiro256(seed: 3)
        let rule = Rule.random(using: &rng)
        XCTAssertThrowsError(try Automaton(width: 2, rule: rule, cells: [0, 0]))
        XCTAssertThrowsError(try Automaton(width: 5, rule: rule, cells: [0, 0, 0]))
        XCTAssertThrowsError(try Automaton(width: 5, rule: rule, cells: [4, 0, 0, 0, 0]))
        XCTAssertThrowsError(try Rule(states: [UInt8](repeating: 0, count: 19)))
        XCTAssertThrowsError(try Rule(states: [4] + [UInt8](repeating: 0, count: 19)))
    }

    // PT-4: the all-zero rule screens as cyclic with period 1.
    func testAllZeroRuleCyclic() throws {
        var rng = Xoshiro256(seed: 4)
        let result = Classifier.evaluate(
            try Rule(states: [UInt8](repeating: 0, count: 20)), using: &rng)
        XCTAssertEqual(result.cyclePeriod, 1)
        XCTAssertFalse(result.maybeIV)
    }

    // PT-5: findCandidate always returns a rule, including the fallback.
    func testFindCandidateAlwaysReturns() {
        var rng = Xoshiro256(seed: 5)
        let (rule, tries) = Classifier.findCandidate(using: &rng, maxTries: 1)
        XCTAssertEqual(tries, 1)
        XCTAssertEqual(rule.states.count, Rule.tableSize)
    }

    // PT-6: current-rule round trip; missing/corrupt loads as absent.
    func testRuleStoreRoundTrip() throws {
        let store = try tempStore()
        XCTAssertNil(store.loadRule())
        var rng = Xoshiro256(seed: 6)
        let rule = Rule.random(using: &rng)
        store.saveRule(rule)
        XCTAssertEqual(store.loadRule(), rule)
        try "not a rule\n".write(
            to: store.stateDir.appendingPathComponent("rule"),
            atomically: true, encoding: .utf8)
        XCTAssertNil(store.loadRule())
    }

    // PT-7: candidate stash round trip in order; invalid lines skipped.
    func testCandidatesRoundTrip() throws {
        let store = try tempStore()
        XCTAssertEqual(store.loadCandidates(), [])
        var rng = Xoshiro256(seed: 7)
        let rules = (0..<5).map { _ in Rule.random(using: &rng) }
        store.saveCandidates(rules)
        XCTAssertEqual(store.loadCandidates(), rules)
        try ("garbage\n" + rules[0].id + "\n").write(
            to: store.stateDir.appendingPathComponent("candidates"),
            atomically: true, encoding: .utf8)
        XCTAssertEqual(store.loadCandidates(), [rules[0]])
    }

    // PT-8: keeper append format and tolerant loading.
    func testKeeperAppendAndLoad() throws {
        let store = try tempStore()
        var rng = Xoshiro256(seed: 8)
        let first = Rule.random(using: &rng)
        let second = Rule.random(using: &rng)
        store.appendInteresting(first)
        store.appendInteresting(second)
        let text = try String(contentsOf: store.keeperFile, encoding: .utf8)
        XCTAssertEqual(text, "rule \(first.id)\nrule \(second.id)\n")
        try (text + "# a comment\nrule notarule\nstray line\n").write(
            to: store.keeperFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.loadInteresting(), [first, second])
    }

    // PT-11: stop() terminates workers; stopping an unstarted search is safe.
    // PT-12: delivered candidates are valid rules.
    func testSearchFindsCandidatesAndStops() {
        CandidateSearch(workers: 1).stop()  // never started: must not hang

        let search = CandidateSearch(workers: 2)
        search.start()
        var found: [Rule] = []
        let deadline = Date().addingTimeInterval(30)
        while found.isEmpty && Date() < deadline {
            found = search.drain()
            Thread.sleep(forTimeInterval: 0.05)
        }
        search.stop()
        XCTAssertFalse(found.isEmpty, "no candidate found within 30s")
        XCTAssertTrue(found.allSatisfy { $0.states.count == Rule.tableSize })
    }
}
