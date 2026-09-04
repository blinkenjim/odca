/// The count-based rule (R-M5..R-M8): 20 next-states, one per canonical
/// neighborhood count vector.

public enum RuleError: Error, Equatable {
    case invalidStates
    case invalidID(String)
}

public struct Rule: Equatable {
    public static let stateCount = 4
    public static let tableSize = 20

    /// The 20 count vectors (n0, n1, n2, n3) with sum 3, in canonical
    /// ascending-lexicographic order (R-M6).
    public static let countVectors: [[Int]] = {
        var vectors: [[Int]] = []
        for n0 in 0...3 {
            for n1 in 0...(3 - n0) {
                for n2 in 0...(3 - n0 - n1) {
                    vectors.append([n0, n1, n2, 3 - n0 - n1 - n2])
                }
            }
        }
        return vectors
    }()

    /// Weighted-sum lookup (informative note in REQTS): states weighted
    /// 0, 1, 4, 16 make the neighborhood sum a unique index 0...48.
    static let weights: [UInt8] = [0, 1, 4, 16]
    static let denseSize = 49

    public let states: [UInt8]
    let dense: [UInt8]

    public init(states: [UInt8]) throws {
        guard states.count == Rule.tableSize,
              states.allSatisfy({ $0 < Rule.stateCount }) else {
            throw RuleError.invalidStates
        }
        self.states = states
        var dense = [UInt8](repeating: 0, count: Rule.denseSize)
        for (i, v) in Rule.countVectors.enumerated() {
            dense[v[1] + 4 * v[2] + 16 * v[3]] = states[i]
        }
        self.dense = dense
    }

    /// Parse a canonical 20-digit base-4 rule ID (R-M8).
    public init(id: String) throws {
        guard id.count == Rule.tableSize else { throw RuleError.invalidID(id) }
        var states: [UInt8] = []
        for ch in id {
            guard let v = ch.wholeNumberValue, (0..<Rule.stateCount).contains(v) else {
                throw RuleError.invalidID(id)
            }
            states.append(UInt8(v))
        }
        try self.init(states: states)
    }

    public var id: String { states.map(String.init).joined() }

    public static func random(using rng: inout some RandomNumberGenerator) -> Rule {
        let states = (0..<tableSize).map { _ in
            UInt8.random(in: 0..<UInt8(stateCount), using: &rng)
        }
        return try! Rule(states: states)
    }

    /// One randomly chosen entry changes to a different state (R-M10).
    public func mutated(using rng: inout some RandomNumberGenerator) -> Rule {
        var states = self.states
        let i = Int.random(in: 0..<Rule.tableSize, using: &rng)
        states[i] = (states[i] + UInt8.random(in: 1...3, using: &rng))
            % UInt8(Rule.stateCount)
        return try! Rule(states: states)
    }

    public static func == (lhs: Rule, rhs: Rule) -> Bool {
        lhs.states == rhs.states
    }
}
