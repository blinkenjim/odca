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
    public private(set) var generation = 0

    public init(width: Int, rule: Rule, cells: [UInt8], wrap: Bool = true) throws {
        guard width >= 3 else { throw AutomatonError.widthTooSmall(width) }
        guard cells.count == width,
              cells.allSatisfy({ $0 < UInt8(Rule.stateCount) }) else {
            throw AutomatonError.invalidCells
        }
        self.width = width
        self.rule = rule
        self.cells = cells
        self.wrap = wrap
    }

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
        generation = 0
    }

    public mutating func resetRandom(using rng: inout some RandomNumberGenerator) {
        cells = Automaton.randomCells(width: width, using: &rng)
        generation = 0
    }

    /// Weighted neighborhood sums (rule-table indices) for the current row.
    public func neighborhoodSums() -> [UInt8] {
        var sums = [UInt8](repeating: 0, count: width)
        for i in 0..<width {
            let own = Rule.weights[Int(cells[i])]
            let left: UInt8
            let right: UInt8
            if wrap {
                left = Rule.weights[Int(cells[(i + width - 1) % width])]
                right = Rule.weights[Int(cells[(i + 1) % width])]
            } else {
                // Cells beyond the edges are permanently state 0 (weight 0).
                left = i == 0 ? 0 : Rule.weights[Int(cells[i - 1])]
                right = i == width - 1 ? 0 : Rule.weights[Int(cells[i + 1])]
            }
            sums[i] = left + own + right
        }
        return sums
    }

    /// Advance one generation and return the new row.
    @discardableResult
    public mutating func step() -> [UInt8] {
        let sums = neighborhoodSums()
        for i in 0..<width {
            cells[i] = rule.dense[Int(sums[i])]
        }
        generation += 1
        return cells
    }
}
