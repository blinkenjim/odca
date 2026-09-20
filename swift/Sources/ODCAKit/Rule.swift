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

    /// R-M12: which rule class this belongs to. `.none` is the ODCA of
    /// R-M5 and everything below reduces to what it always did.
    public let experiment: Experiment
    public let states: [UInt8]
    let dense: [UInt8]
    /// Which states the rule can write, precomputed beside `dense`. The
    /// census of R-A1 asks this of every generation and the answer depends
    /// on the table alone, so it is settled once here rather than rebuilt
    /// on each row.
    public let producible: [Bool]

    public init(states: [UInt8], experiment: Experiment = .none) throws {
        guard states.count == experiment.tableSize,
              states.allSatisfy({ $0 < Rule.stateCount }) else {
            throw RuleError.invalidStates
        }
        self.experiment = experiment
        self.states = states
        // One dense lookup per grandparent state under `modal`, one
        // otherwise; a weighted neighborhood sum indexes within it (R-M7).
        let span = experiment.denseSize
        var dense = [UInt8](repeating: 0, count: span * (experiment == .modal ? Rule.stateCount : 1))
        for (i, v) in experiment.countVectors.enumerated() {
            let at = experiment.denseIndex(of: v)
            if experiment == .modal {
                for g in 0..<Rule.stateCount { dense[g * span + at] = states[i * Rule.stateCount + g] }
            } else {
                dense[at] = states[i]
            }
        }
        self.dense = dense
        var producible = [Bool](repeating: false, count: Rule.stateCount)
        for state in states { producible[Int(state)] = true }
        self.producible = producible
    }

    /// Parse a canonical base-4 rule ID (R-M8): 20 digits, or as many as
    /// the experiment's table has (R-M12).
    public init(id: String, experiment: Experiment = .none) throws {
        guard id.count == experiment.tableSize else { throw RuleError.invalidID(id) }
        var states: [UInt8] = []
        for ch in id {
            guard let v = ch.wholeNumberValue, (0..<Rule.stateCount).contains(v) else {
                throw RuleError.invalidID(id)
            }
            states.append(UInt8(v))
        }
        try self.init(states: states, experiment: experiment)
    }

    public var id: String { states.map(String.init).joined() }

    public static func random(using rng: inout some RandomNumberGenerator,
                              experiment: Experiment = .none) -> Rule {
        let states = (0..<experiment.tableSize).map { _ in
            UInt8.random(in: 0..<UInt8(stateCount), using: &rng)
        }
        return try! Rule(states: states, experiment: experiment)
    }

    /// One randomly chosen entry changes to a different state (R-M10).
    public func mutated(using rng: inout some RandomNumberGenerator) -> Rule {
        var states = self.states
        let i = Int.random(in: 0..<experiment.tableSize, using: &rng)
        states[i] = (states[i] + UInt8.random(in: 1...3, using: &rng))
            % UInt8(Rule.stateCount)
        return try! Rule(states: states, experiment: experiment)
    }

    public static func == (lhs: Rule, rhs: Rule) -> Bool {
        lhs.states == rhs.states && lhs.experiment == rhs.experiment
    }
}
