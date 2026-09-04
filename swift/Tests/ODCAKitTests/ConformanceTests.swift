import Foundation
import XCTest

@testable import ODCAKit

/// Layer 1 of TESTS.md: run the shared golden vectors against this engine.
final class ConformanceTests: XCTestCase {
    struct Vectors: Decodable {
        struct EvolutionCase: Decodable {
            let name: String
            let rule: String
            let wrap: Bool
            let initial: String
            let generations: Int
            let expected: [String]
        }

        let count_vectors: [[Int]]
        let valid_rule_ids: [String]
        let invalid_rule_ids: [String]
        let evolution: [EvolutionCase]
    }

    static let vectors: Vectors = {
        // swift/Tests/ODCAKitTests/ConformanceTests.swift -> repo root.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ODCAKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // swift
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("conformance/vectors.json")
        return try! JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }()

    func testCountVectorCanonicalOrder() {
        XCTAssertEqual(Rule.countVectors, Self.vectors.count_vectors)
    }

    func testValidRuleIDsRoundTrip() throws {
        for id in Self.vectors.valid_rule_ids {
            XCTAssertEqual(try Rule(id: id).id, id)
        }
    }

    func testInvalidRuleIDsRejected() {
        for id in Self.vectors.invalid_rule_ids {
            XCTAssertThrowsError(try Rule(id: id), "accepted invalid ID \(id)")
        }
    }

    func testEvolution() throws {
        for testCase in Self.vectors.evolution {
            let initial = testCase.initial.map { UInt8($0.wholeNumberValue!) }
            var automaton = try Automaton(
                width: initial.count, rule: Rule(id: testCase.rule),
                cells: initial, wrap: testCase.wrap)
            for (generation, expected) in testCase.expected.enumerated() {
                let actual = automaton.step().map(String.init).joined()
                XCTAssertEqual(
                    actual, expected,
                    "\(testCase.name): generation \(generation + 1) diverged")
            }
        }
    }
}
