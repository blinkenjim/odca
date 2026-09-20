/// The automaton engine (R-M1..R-M9): a fixed-width row of 4-state cells
/// evolving synchronously under a count-based Rule.

public enum AutomatonError: Error, Equatable {
    case widthTooSmall(Int)
    case invalidCells
}

public struct Automaton {
    public let width: Int
    public var wrap: Bool
    public var rule: Rule
    public private(set) var cells: [UInt8]
    /// R-M12: the row before the current one, which a second-order rule
    /// reads as each cell's grandparent. Kept for every rule class so the
    /// boringness detector can judge the pair (R-A1); case 0 ignores it.
    public private(set) var previous: [UInt8]
    public private(set) var generation = 0

    public init(width: Int, rule: Rule, cells: [UInt8], previous: [UInt8]? = nil,
                wrap: Bool = true) throws {
        guard width >= 3 else { throw AutomatonError.widthTooSmall(width) }
        guard cells.count == width,
              cells.allSatisfy({ $0 < UInt8(Rule.stateCount) }) else {
            throw AutomatonError.invalidCells
        }
        if let previous = previous {
            guard previous.count == width,
                  previous.allSatisfy({ $0 < UInt8(Rule.stateCount) }) else {
                throw AutomatonError.invalidCells
            }
        }
        self.width = width
        self.rule = rule
        self.cells = cells
        // With no row before it, a seed is its own grandparent: the
        // automaton starts as though it had been still.
        self.previous = previous ?? cells
        self.wrap = wrap
    }

    /// The pair that is really the state of a second-order automaton
    /// (R-M12): the visible row and the one behind it. The boringness
    /// detector compares these rather than the row alone, since the same
    /// row reached from two different pasts has two different futures.
    public var state: [UInt8] { rule.experiment.secondOrder ? cells + previous : cells }

    public static func randomCells(
        width: Int, using rng: inout some RandomNumberGenerator
    ) -> [UInt8] {
        (0..<width).map { _ in UInt8.random(in: 0..<UInt8(Rule.stateCount), using: &rng) }
    }

    public mutating func reset(cells: [UInt8]) throws {
        guard cells.count == width,
              cells.allSatisfy({ $0 < UInt8(Rule.stateCount) }) else {
            throw AutomatonError.invalidCells
        }
        self.cells = cells
        self.previous = cells
        generation = 0
    }

    public mutating func resetRandom(using rng: inout some RandomNumberGenerator) {
        cells = Automaton.randomCells(width: width, using: &rng)
        // A second-order automaton needs two rows to start from, and two
        // independent ones give it somewhere to go: seeding the grandparent
        // equal to the seed starts every run from a standstill.
        previous = rule.experiment.secondOrder
            ? Automaton.randomCells(width: width, using: &rng) : cells
        generation = 0
    }

    /// Weighted neighborhood sums (rule-table indices) for the current row.
    /// Under R-M12's totalistic4 the grandparent is counted as a fourth
    /// cell, so the weights are that experiment's, not case 0's.
    public func neighborhoodSums() -> [UInt8] {
        let w = rule.experiment.weights
        let counts4 = rule.experiment == .totalistic4
        var sums = [UInt8](repeating: 0, count: width)
        for i in 0..<width {
            let own = w[Int(cells[i])]
            let left: UInt8
            let right: UInt8
            if wrap {
                left = w[Int(cells[(i + width - 1) % width])]
                right = w[Int(cells[(i + 1) % width])]
            } else {
                // Cells beyond the edges are permanently state 0 (weight 0).
                left = i == 0 ? 0 : w[Int(cells[i - 1])]
                right = i == width - 1 ? 0 : w[Int(cells[i + 1])]
            }
            sums[i] = left + own + right + (counts4 ? w[Int(previous[i])] : 0)
        }
        return sums
    }

    /// Advance one generation and return the new row.
    @discardableResult
    public mutating func step() -> [UInt8] {
        let sums = neighborhoodSums()
        let span = rule.experiment.denseSize
        var next = cells
        switch rule.experiment {
        case .none, .totalistic4:
            for i in 0..<width { next[i] = rule.dense[Int(sums[i])] }
        case .modal:  // the grandparent picks the column
            for i in 0..<width { next[i] = rule.dense[Int(previous[i]) * span + Int(sums[i])] }
        case .fredkin:  // reversible: subtract the grandparent, mod 4
            let n = UInt8(Rule.stateCount)
            for i in 0..<width {
                next[i] = (rule.dense[Int(sums[i])] + n - previous[i]) % n
            }
        }
        previous = cells
        cells = next
        generation += 1
        return cells
    }
}
